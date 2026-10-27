// Veldsensor: firmware for one soil-moisture sensor box (ESP32 + the Bits & Parts LM393 sensor).
//
// Every MEET_INTERVAL_MINUTEN the box wakes from deep sleep, powers the sensor from a GPIO,
// reads its analog output and stores the value in RTC memory. Then it tries to join the
// iPhone's Personal Hotspot and sends every unsent measurement (format "veld/sensorupload",
// see sensor/README.md):
// - to the central system in the cloud (HTTPS, Supabase RPC sensor_upload with the sensor's
//   key), when CLOUD_PROJECT is set; the app need not be open;
// - otherwise, or when the cloud does not answer, to the Veldvlucht app at
//   http://<gateway>:8787/sensormetingen.
// Measurements are only removed after an answer 200. Then WiFi off and back to sleep.
//
// The box has no real clock. It stores the ESP32 system time (which keeps running in deep
// sleep) and sends each measurement's age in seconds; the app turns that into a time.
// Each measurement also gets a number, counted since the box was switched on ("boot" is a
// random id of that start), so the app can skip measurements it already has.
// Pressing the BOOT button wakes the box: it measures and sends right away.
// Unsent measurements are lost when the power goes off, on the reset button or a new upload.
//
// Settings live in Instellingen.h (a copy of Instellingen.voorbeeld.h, never in git).
// Serial output (115200 baud) is in Dutch for the owner.

#if !__has_include("Instellingen.h")
#error "Instellingen.h ontbreekt. Kopieer Instellingen.voorbeeld.h naar Instellingen.h (in dezelfde map) en vul je hotspot in. Zie sensor/README.md."
#else
#include "Instellingen.h"
#if !defined(HOTSPOT_NAAM) || !defined(HOTSPOT_WACHTWOORD) || !defined(SENSOR_ID) || !defined(DIEPTE_CM) \
  || !defined(MEET_INTERVAL_MINUTEN) || !defined(TESTMODUS) || !defined(SENSOR_VOEDING_PIN) \
  || !defined(SENSOR_PIN) || !defined(BATTERIJ_PIN) || !defined(BATTERIJ_DELER)
#error "Instellingen.h is niet compleet. Vergelijk hem met Instellingen.voorbeeld.h."
#endif
// Older settings files have no cloud: then the box only sends to the app.
#ifndef CLOUD_PROJECT
#define CLOUD_PROJECT ""
#endif
#ifndef CLOUD_SLEUTEL
#define CLOUD_SLEUTEL ""
#endif
#ifndef SENSOR_SLEUTEL
#define SENSOR_SLEUTEL ""
#endif
#endif

#include <WiFi.h>
#include <NetworkClientSecure.h>
#include <HTTPClient.h>
#include <esp_sleep.h>
#include <time.h>

// ---- Checks on the board and the settings, so mistakes show up when compiling ----

#if !CONFIG_IDF_TARGET_ESP32
#error "Deze schets is voor een gewone ESP32. Kies in de Arduino IDE het bord \"ESP32 Dev Module\"."
#endif

static_assert(sizeof(HOTSPOT_NAAM) <= 33, "HOTSPOT_NAAM is te lang (hoogstens 32 tekens).");
static_assert(sizeof(HOTSPOT_WACHTWOORD) <= 64, "HOTSPOT_WACHTWOORD is te lang (hoogstens 63 tekens).");
static_assert(sizeof(SENSOR_ID) > 1, "SENSOR_ID mag niet leeg zijn.");
static_assert(DIEPTE_CM >= 0, "DIEPTE_CM kan niet negatief zijn.");
static_assert(MEET_INTERVAL_MINUTEN >= 1, "MEET_INTERVAL_MINUTEN moet minstens 1 zijn.");
static_assert(sizeof(CLOUD_PROJECT) <= 41, "CLOUD_PROJECT is te lang: alleen de letters voor .supabase.co.");
static_assert(sizeof(CLOUD_PROJECT) == 1 || (sizeof(CLOUD_SLEUTEL) > 1 && sizeof(SENSOR_SLEUTEL) > 1),
              "Met CLOUD_PROJECT zijn ook CLOUD_SLEUTEL en SENSOR_SLEUTEL nodig (zie de app).");
static_assert(SENSOR_PIN >= 32 && SENSOR_PIN <= 39,
              "SENSOR_PIN moet GPIO 32 t/m 39 zijn: de andere analoge pinnen werken niet als de wifi aan staat.");
static_assert(BATTERIJ_PIN == -1 || (BATTERIJ_PIN >= 32 && BATTERIJ_PIN <= 39 && BATTERIJ_PIN != SENSOR_PIN),
              "BATTERIJ_PIN moet -1 zijn, of GPIO 32 t/m 39 (en niet dezelfde pin als SENSOR_PIN).");
static_assert(SENSOR_VOEDING_PIN >= 0 && SENSOR_VOEDING_PIN <= 33 && !(SENSOR_VOEDING_PIN >= 6 && SENSOR_VOEDING_PIN <= 11),
              "SENSOR_VOEDING_PIN moet een uitgang zijn: niet GPIO 6 t/m 11 (flashgeheugen) en niet 34 t/m 39 (alleen ingang).");

// ---- Fixed values ----

constexpr uint16_t APP_POORT = 8787;           // the Veldvlucht app listens here
constexpr uint16_t MAX_BEWAARD = 200;          // unsent measurements kept; 200 = about 8 days at one per hour
constexpr uint8_t AANTAL_SAMPLES = 10;         // analogRead samples per measurement
constexpr uint32_t OPWARMTIJD_MS = 200;        // sensor settles after switching it on
constexpr uint32_t WIFI_TIMEOUT_MS = 10000;    // give up joining the hotspot after this
constexpr uint32_t TEST_INTERVAL_MS = 10000;   // one measurement every 10 s in TESTMODUS

// ---- Unsent measurements, kept in RTC memory (survives deep sleep, not a power loss) ----

struct Meting {
  uint32_t nr;          // number of the measurement since the box was switched on
  uint32_t tijdS;       // system time in seconds when measured
  uint16_t ruw;         // ADC value 0-4095; with this sensor higher usually means drier
  uint16_t batterijMv;  // battery voltage in millivolts; 0 = not measured
};

// A ring buffer: bewaardBegin is the oldest, bewaardAantal how many there are.
RTC_DATA_ATTR Meting bewaard[MAX_BEWAARD];
RTC_DATA_ATTR uint16_t bewaardBegin = 0;
RTC_DATA_ATTR uint16_t bewaardAantal = 0;
// A random id of this start and the last measurement number; both start again after a power loss.
RTC_DATA_ATTR uint32_t opstartId = 0;
RTC_DATA_ATTR uint32_t volgnummer = 0;

static uint32_t nuS() {
  // Starts at 0 on power-on and keeps counting through deep sleep. Never set to the real time.
  return (uint32_t)time(nullptr);
}

static Meting &bewaardeMeting(uint16_t i) {  // i = 0 is the oldest
  return bewaard[(bewaardBegin + i) % MAX_BEWAARD];
}

static void bewaar(const Meting &m) {
  if (bewaardAantal == MAX_BEWAARD) {
    // Memory full: drop the oldest, so the newest measurements survive.
    bewaardBegin = (bewaardBegin + 1) % MAX_BEWAARD;
    bewaardAantal--;
    Serial.println("Geheugen vol: de oudste meting is weggegooid.");
  }
  bewaardeMeting(bewaardAantal) = m;
  bewaardAantal++;
}

static void verwijderOudste(uint16_t aantal) {
  if (aantal > bewaardAantal) aantal = bewaardAantal;
  bewaardBegin = (bewaardBegin + aantal) % MAX_BEWAARD;
  bewaardAantal -= aantal;
}

// ---- Measuring ----

// Median of the samples: one odd reading does not move it, unlike the average.
static uint16_t mediaan(uint16_t *waarden, uint8_t n) {
  for (uint8_t i = 1; i < n; i++) {  // insertion sort, n is small
    uint16_t x = waarden[i];
    uint8_t j = i;
    while (j > 0 && waarden[j - 1] > x) {
      waarden[j] = waarden[j - 1];
      j--;
    }
    waarden[j] = x;
  }
  return (n % 2) ? waarden[n / 2] : (uint16_t)((waarden[n / 2 - 1] + waarden[n / 2] + 1) / 2);
}

static Meting meet() {
  Meting m{};
  m.nr = ++volgnummer;
  m.tijdS = nuS();

  // Power the sensor only while measuring: current through the bare metal probe makes it
  // corrode much faster.
  digitalWrite(SENSOR_VOEDING_PIN, HIGH);
  delay(OPWARMTIJD_MS);
  uint16_t waarden[AANTAL_SAMPLES];
  for (uint8_t i = 0; i < AANTAL_SAMPLES; i++) {
    waarden[i] = analogRead(SENSOR_PIN);
    delay(10);
  }
  digitalWrite(SENSOR_VOEDING_PIN, LOW);
  m.ruw = mediaan(waarden, AANTAL_SAMPLES);

#if BATTERIJ_PIN >= 0
  uint32_t somMv = 0;
  for (uint8_t i = 0; i < AANTAL_SAMPLES; i++) {
    somMv += analogReadMilliVolts(BATTERIJ_PIN);
    delay(2);
  }
  m.batterijMv = (uint16_t)lround((double)somMv / AANTAL_SAMPLES * BATTERIJ_DELER);
#endif
  return m;
}

// ---- Upload (format "veld/sensorupload", version 0) ----

// Appends s as a JSON string, with quotes and the escapes JSON needs.
static void voegJsonTekstToe(String &uit, const char *s) {
  uit += '"';
  for (; *s; s++) {
    const char c = *s;
    if (c == '"' || c == '\\') {
      uit += '\\';
      uit += c;
    } else if ((unsigned char)c < 0x20) {
      char escape[8];
      snprintf(escape, sizeof escape, "\\u%04x", (unsigned)c);
      uit += escape;
    } else {
      uit += c;
    }
  }
  uit += '"';
}

// The upload body for the oldest `aantal` stored measurements, oldest first.
// ageS is the number of whole seconds between each measurement and `nu`.
static String maakUpload(uint16_t aantal, uint32_t nu) {
  String body;
  body.reserve(144 + aantal * 68);
  body += "{\"format\":\"veld/sensorupload\",\"version\":0,\"sensorId\":";
  voegJsonTekstToe(body, SENSOR_ID);
  body += ",\"depthCm\":";
  body += (int)DIEPTE_CM;
  body += ",\"boot\":";
  body += String(opstartId);
  body += ",\"measurements\":[";
  for (uint16_t i = 0; i < aantal; i++) {
    const Meting &m = bewaardeMeting(i);
    char batterij[16] = "null";
    if (m.batterijMv > 0) {
      const unsigned centivolt = (m.batterijMv + 5u) / 10u;  // round to 0.01 V without floats
      snprintf(batterij, sizeof batterij, "%u.%02u", centivolt / 100u, centivolt % 100u);
    }
    const uint32_t ouderdomS = nu >= m.tijdS ? nu - m.tijdS : 0;
    char item[128];
    snprintf(item, sizeof item, "%s{\"nr\":%lu,\"ageS\":%lu,\"raw\":%u,\"batteryVolt\":%s}", i > 0 ? "," : "",
             (unsigned long)m.nr, (unsigned long)ouderdomS, (unsigned)m.ruw, batterij);
    body += item;
  }
  body += "]}";
  return body;
}

// Sends all stored measurements to the central system in the cloud. True when it answered 200.
static bool verstuurNaarCloud(uint16_t aantal) {
  const String url = String("https://") + CLOUD_PROJECT + ".supabase.co/rest/v1/rpc/sensor_upload";
  Serial.printf("Versturen van %u meting(en) naar de cloud ...\n", (unsigned)aantal);

  NetworkClientSecure verbinding;
  verbinding.useBuiltinCACertBundle();  // checks the server's certificate, like a browser
  HTTPClient http;
  http.setConnectTimeout(8000);
  http.setTimeout(15000);
  http.setReuse(false);
  if (!http.begin(verbinding, url)) {
    Serial.println("  Ongeldig cloudadres. Klopt CLOUD_PROJECT?");
    return false;
  }
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", CLOUD_SLEUTEL);
  if (strncmp(CLOUD_SLEUTEL, "eyJ", 3) == 0) {
    http.addHeader("Authorization", String("Bearer ") + CLOUD_SLEUTEL);  // the older "anon" keys
  }
  String body = "{\"p_sleutel\":";
  voegJsonTekstToe(body, SENSOR_SLEUTEL);
  body += ",\"p_upload\":";
  body += maakUpload(aantal, nuS());
  body += "}";

  const int code = http.POST(body);
  bool gelukt = false;
  if (code == 200) {
    Serial.printf("  Gelukt. De cloud zegt: %s\n", http.getString().c_str());
    gelukt = true;
  } else if (code > 0) {
    Serial.printf("  De cloud antwoordde met code %d: %s\n", code, http.getString().c_str());
    if (code == 401 || code == 403) {
      Serial.println("  Klopt SENSOR_SLEUTEL en CLOUD_SLEUTEL? Kijk in de app.");
    }
  } else {
    Serial.printf("  Cloud niet bereikbaar (%s). Heeft de hotspot internet?\n", HTTPClient::errorToString(code).c_str());
  }
  http.end();
  return gelukt;
}

// Sends all stored measurements: to the cloud when it is set up, else (or when the cloud
// does not answer) to the app. Removes them only after an answer 200.
static void verstuur() {
  const uint16_t aantal = bewaardAantal;
  if (CLOUD_PROJECT[0] != '\0') {
    if (verstuurNaarCloud(aantal)) {
      verwijderOudste(aantal);
      return;
    }
    Serial.println("  Dan naar de app.");
  }
  // On a Personal Hotspot the iPhone is the gateway, normally 172.20.10.1.
  char url[64];
  snprintf(url, sizeof url, "http://%s:%u/sensormetingen", WiFi.gatewayIP().toString().c_str(), (unsigned)APP_POORT);
  Serial.printf("Versturen van %u meting(en) naar %s ...\n", (unsigned)aantal, url);

  WiFiClient verbinding;
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(10000);
  http.setReuse(false);  // sends "Connection: close"
  if (!http.begin(verbinding, url)) {
    Serial.println("  Ongeldig adres. De metingen blijven bewaard.");
    return;
  }
  http.addHeader("Content-Type", "application/json");

  const int code = http.POST(maakUpload(aantal, nuS()));
  if (code == 200) {
    verwijderOudste(aantal);
    Serial.printf("  Gelukt. De app zegt: %s\n", http.getString().c_str());
  } else if (code > 0) {
    Serial.printf("  De app antwoordde met code %d: %s\n", code, http.getString().c_str());
    Serial.println("  De metingen blijven bewaard.");
  } else {
    Serial.printf("  App niet bereikbaar (%s).\n", HTTPClient::errorToString(code).c_str());
    Serial.println("  Is de Veldvlucht-app open op de iPhone? De metingen blijven bewaard.");
  }
  http.end();
}

// ---- WiFi ----

// Joins the hotspot, sends if that worked, and switches WiFi off again.
static void verbindEnVerstuur() {
  if (HOTSPOT_NAAM[0] == '\0') {
    Serial.println("Geen hotspot ingevuld in Instellingen.h: niet versturen.");
    return;
  }
  Serial.printf("Verbinden met hotspot \"%s\" ... ", HOTSPOT_NAAM);
  WiFi.persistent(false);  // don't write the hotspot to flash on every wake-up
  WiFi.mode(WIFI_STA);
  WiFi.begin(HOTSPOT_NAAM, HOTSPOT_WACHTWOORD);
  const uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS) {
    delay(100);
  }

  const wl_status_t status = WiFi.status();
  if (status == WL_CONNECTED) {
    Serial.printf("verbonden na %.1f s.\n", (millis() - start) / 1000.0);
    verstuur();
  } else {
    Serial.println("niet gelukt.");
    if (status == WL_NO_SSID_AVAIL) {
      Serial.println("  Hotspot niet gevonden. Staat hij aan, met \"Maximaliseer compatibiliteit\" aan?");
      Serial.println("  Klopt de naam precies (hoofdletters, spaties)?");
    } else {
      Serial.println("  Klopt het wachtwoord? Is de iPhone dichtbij?");
    }
    Serial.println("  De metingen blijven bewaard.");
  }

  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
}

// ---- One cycle: measure, keep, try to send ----

static void meetEnVerstuur() {
  const Meting m = meet();
  bewaar(m);
  Serial.printf("Gemeten: ruw %u (hoger = droger)", (unsigned)m.ruw);
  if (m.batterijMv > 0) {
    Serial.printf(", batterij %.2f V", m.batterijMv / 1000.0);
  }
  Serial.println(".");
  Serial.printf("Nog te versturen: %u meting(en), de oudste van %lu min geleden.\n", (unsigned)bewaardAantal,
                (unsigned long)((nuS() - bewaardeMeting(0).tijdS) / 60));

  verbindEnVerstuur();
}

static void slaap() {
  // Subtract the time awake, so measurements stay about MEET_INTERVAL_MINUTEN apart.
  const uint64_t intervalUs = (uint64_t)MEET_INTERVAL_MINUTEN * 60ULL * 1000000ULL;
  const uint64_t wakkerUs = (uint64_t)millis() * 1000ULL;
  const uint64_t slaapUs = intervalUs > wakkerUs + 1000000ULL ? intervalUs - wakkerUs : 1000000ULL;
  Serial.printf("Wifi uit. Slapen tot de volgende meting, over %lu s. Druk op BOOT om meteen te meten en te versturen.\n",
                (unsigned long)(slaapUs / 1000000ULL));
  Serial.flush();
  esp_sleep_enable_timer_wakeup(slaapUs);
  esp_sleep_enable_ext0_wakeup(GPIO_NUM_0, 0);  // the BOOT button pulls GPIO 0 low
  esp_deep_sleep_start();
}

void setup() {
  Serial.begin(115200);
  pinMode(SENSOR_VOEDING_PIN, OUTPUT);
  digitalWrite(SENSOR_VOEDING_PIN, LOW);
  analogReadResolution(12);       // 0-4095
  analogSetAttenuation(ADC_11db);  // measures up to about 3.1 V; applies to pins on their first read
  if (bewaardBegin >= MAX_BEWAARD || bewaardAantal > MAX_BEWAARD) {  // should never happen
    bewaardBegin = 0;
    bewaardAantal = 0;
  }
  if (opstartId == 0) {  // a new start: RTC memory is cleared on power-on and reset
    opstartId = esp_random() | 1u;
    volgnummer = 0;
  }

  Serial.println();
  Serial.printf("=== Sensorkastje %s ===\n", SENSOR_ID);
  const esp_sleep_wakeup_cause_t oorzaak = esp_sleep_get_wakeup_cause();
  if (oorzaak == ESP_SLEEP_WAKEUP_TIMER) {
    Serial.println("Wakker na het slapen.");
  } else if (oorzaak == ESP_SLEEP_WAKEUP_EXT0) {
    Serial.println("BOOT-knop ingedrukt: nu meten en versturen.");
  } else {
    Serial.println("Opgestart (stroom aan, resetknop of nieuwe upload).");
  }

  if (TESTMODUS) {
    Serial.println("TESTMODUS: elke 10 s meten, zonder slapen. Zet TESTMODUS op false voor het veld.");
    return;  // loop() takes over
  }
  meetEnVerstuur();
  slaap();
}

void loop() {
  // Only reached in TESTMODUS; otherwise the box goes to sleep at the end of setup().
  const uint32_t start = millis();
  meetEnVerstuur();
  const uint32_t bezig = millis() - start;
  if (bezig < TEST_INTERVAL_MS) {
    delay(TEST_INTERVAL_MS - bezig);
  }
  Serial.println();
}
