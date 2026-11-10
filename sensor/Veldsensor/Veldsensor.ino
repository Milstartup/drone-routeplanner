// Veldsensor: firmware for one soil-moisture sensor box (ESP32 + the Bits & Parts LM393 sensor).
//
// Every measuring interval (60 minutes unless set otherwise) the box wakes from deep sleep, powers the sensor from a GPIO,
// reads its analog output and stores the value in RTC memory. Then it tries to join the
// iPhone's Personal Hotspot and sends every unsent measurement (format "veld/sensorupload",
// see sensor/README.md):
// - to the central system in the cloud (HTTPS, Supabase RPC sensor_upload with the sensor's
//   key), when it has a cloud project; the app need not be open;
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
// Pairing (10 November 2026): after switching on, the box opens its own WiFi network
// "Veldsensor-XXXX" for two minutes (until it has settings, for good). The Veldvlucht app,
// or a browser at http://192.168.4.1, sends it the hotspot, the sensor's name and key and the
// cloud; the box keeps them in flash. Instellingen.h is optional: its values are the defaults,
// and the pins and the test mode live there. Waking from deep sleep never opens the network.
// Serial output (115200 baud) is in Dutch for the owner.

#if __has_include("Instellingen.h")
#include "Instellingen.h"
#endif
// Defaults, so the box also works without Instellingen.h: then you pair it with the app.
#ifndef HOTSPOT_NAAM
#define HOTSPOT_NAAM ""
#endif
#ifndef HOTSPOT_WACHTWOORD
#define HOTSPOT_WACHTWOORD ""
#endif
#ifndef SENSOR_ID
#define SENSOR_ID ""
#endif
#ifndef CLOUD_PROJECT
#define CLOUD_PROJECT ""
#endif
#ifndef CLOUD_SLEUTEL
#define CLOUD_SLEUTEL ""
#endif
#ifndef SENSOR_SLEUTEL
#define SENSOR_SLEUTEL ""
#endif
#ifndef DIEPTE_CM
#define DIEPTE_CM 15
#endif
#ifndef MEET_INTERVAL_MINUTEN
#define MEET_INTERVAL_MINUTEN 60
#endif
#ifndef TESTMODUS
#define TESTMODUS false
#endif
#ifndef SENSOR_VOEDING_PIN
#define SENSOR_VOEDING_PIN 25
#endif
#ifndef SENSOR_PIN
#define SENSOR_PIN 34
#endif
#ifndef BATTERIJ_PIN
#define BATTERIJ_PIN -1
#endif
#ifndef BATTERIJ_DELER
#define BATTERIJ_DELER 2.0
#endif

#include <WiFi.h>
#include <NetworkClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <Preferences.h>
#include <esp_sleep.h>
#include <time.h>

// ---- Checks on the board and the settings, so mistakes show up when compiling ----

#if !CONFIG_IDF_TARGET_ESP32
#error "Deze schets is voor een gewone ESP32. Kies in de Arduino IDE het bord \"ESP32 Dev Module\"."
#endif

static_assert(sizeof(HOTSPOT_NAAM) <= 33, "HOTSPOT_NAAM is te lang (hoogstens 32 tekens).");
static_assert(sizeof(HOTSPOT_WACHTWOORD) <= 64, "HOTSPOT_WACHTWOORD is te lang (hoogstens 63 tekens).");
static_assert(sizeof(SENSOR_ID) <= 41, "SENSOR_ID is te lang (hoogstens 40 tekens).");
static_assert(DIEPTE_CM >= 0, "DIEPTE_CM kan niet negatief zijn.");
static_assert(MEET_INTERVAL_MINUTEN >= 1, "MEET_INTERVAL_MINUTEN moet minstens 1 zijn.");
static_assert(sizeof(CLOUD_PROJECT) <= 41, "CLOUD_PROJECT is te lang: alleen de letters voor .supabase.co.");
static_assert(sizeof(CLOUD_SLEUTEL) <= 257 && sizeof(SENSOR_SLEUTEL) <= 65, "CLOUD_SLEUTEL of SENSOR_SLEUTEL is te lang.");
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
constexpr uint32_t KOPPEL_MS = 2 * 60 * 1000;  // the pairing network stays open this long after switching on
// The pairing network's password. Everybody may know it; it only keeps passers-by from joining
// by accident, and the box only listens for two minutes.
constexpr const char *KOPPEL_WACHTWOORD = "veldsensor";

// ---- Settings: Instellingen.h first, then what the app sent (kept in flash) ----

struct Instellingen {
  char hotspotNaam[33];
  char hotspotWachtwoord[64];
  char sensorId[41];
  char sensorSleutel[65];
  char cloudProject[41];
  char cloudSleutel[257];  // publishable keys are short, the older "anon" keys about 200 characters
  uint16_t diepteCm;
  uint16_t intervalMinuten;
};
static Instellingen inst;

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

// ---- Loading and saving the settings ----

static void laadInstellingen() {
  strlcpy(inst.hotspotNaam, HOTSPOT_NAAM, sizeof inst.hotspotNaam);
  strlcpy(inst.hotspotWachtwoord, HOTSPOT_WACHTWOORD, sizeof inst.hotspotWachtwoord);
  strlcpy(inst.sensorId, SENSOR_ID, sizeof inst.sensorId);
  strlcpy(inst.sensorSleutel, SENSOR_SLEUTEL, sizeof inst.sensorSleutel);
  strlcpy(inst.cloudProject, CLOUD_PROJECT, sizeof inst.cloudProject);
  strlcpy(inst.cloudSleutel, CLOUD_SLEUTEL, sizeof inst.cloudSleutel);
  inst.diepteCm = DIEPTE_CM;
  inst.intervalMinuten = MEET_INTERVAL_MINUTEN;

  Preferences flash;
  if (!flash.begin("veldsensor", true)) return;  // never paired: no namespace yet
  if (flash.isKey("sensor")) {
    strlcpy(inst.hotspotNaam, flash.getString("hotspot").c_str(), sizeof inst.hotspotNaam);
    strlcpy(inst.hotspotWachtwoord, flash.getString("wachtwoord").c_str(), sizeof inst.hotspotWachtwoord);
    strlcpy(inst.sensorId, flash.getString("sensor").c_str(), sizeof inst.sensorId);
    strlcpy(inst.sensorSleutel, flash.getString("sleutel").c_str(), sizeof inst.sensorSleutel);
    strlcpy(inst.cloudProject, flash.getString("project").c_str(), sizeof inst.cloudProject);
    strlcpy(inst.cloudSleutel, flash.getString("cloudsleutel").c_str(), sizeof inst.cloudSleutel);
    inst.diepteCm = flash.getUShort("diepte", inst.diepteCm);
    inst.intervalMinuten = flash.getUShort("interval", inst.intervalMinuten);
  }
  flash.end();
}

static bool bewaarInstellingen(const Instellingen &n) {
  Preferences flash;
  if (!flash.begin("veldsensor", false)) return false;
  bool gelukt = flash.putString("hotspot", n.hotspotNaam) == strlen(n.hotspotNaam)
             && flash.putString("wachtwoord", n.hotspotWachtwoord) == strlen(n.hotspotWachtwoord)
             && flash.putString("sleutel", n.sensorSleutel) == strlen(n.sensorSleutel)
             && flash.putString("project", n.cloudProject) == strlen(n.cloudProject)
             && flash.putString("cloudsleutel", n.cloudSleutel) == strlen(n.cloudSleutel)
             && flash.putUShort("diepte", n.diepteCm) == 2
             && flash.putUShort("interval", n.intervalMinuten) == 2;
  // The sensor name last: loading takes the flash settings only when it is there.
  gelukt = gelukt && flash.putString("sensor", n.sensorId) == strlen(n.sensorId);
  flash.end();
  return gelukt;
}

static bool gekoppeld() {
  return inst.hotspotNaam[0] != '\0' && inst.sensorId[0] != '\0';
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

// The sensor's raw value now, without keeping it.
static uint16_t leesSensor() {
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
  return mediaan(waarden, AANTAL_SAMPLES);
}

static Meting meet() {
  Meting m{};
  m.nr = ++volgnummer;
  m.tijdS = nuS();
  m.ruw = leesSensor();

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
  voegJsonTekstToe(body, inst.sensorId);
  body += ",\"depthCm\":";
  body += (int)inst.diepteCm;
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
  const String url = String("https://") + inst.cloudProject + ".supabase.co/rest/v1/rpc/sensor_upload";
  Serial.printf("Versturen van %u meting(en) naar de cloud ...\n", (unsigned)aantal);

  NetworkClientSecure verbinding;
  verbinding.useBuiltinCACertBundle();  // checks the server's certificate, like a browser
  HTTPClient http;
  http.setConnectTimeout(8000);
  http.setTimeout(15000);
  http.setReuse(false);
  if (!http.begin(verbinding, url)) {
    Serial.println("  Ongeldig cloudadres. Koppel het kastje opnieuw met de app.");
    return false;
  }
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", inst.cloudSleutel);
  if (strncmp(inst.cloudSleutel, "eyJ", 3) == 0) {
    http.addHeader("Authorization", String("Bearer ") + inst.cloudSleutel);  // the older "anon" keys
  }
  String body = "{\"p_sleutel\":";
  voegJsonTekstToe(body, inst.sensorSleutel);
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
      Serial.println("  De sleutel klopt niet. Bewaar de sensor in de app en koppel het kastje opnieuw.");
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
  if (inst.cloudProject[0] != '\0') {
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
  if (inst.hotspotNaam[0] == '\0') {
    Serial.println("Nog geen hotspot: koppel het kastje met de app. Niet versturen.");
    return;
  }
  Serial.printf("Verbinden met hotspot \"%s\" ... ", inst.hotspotNaam);
  WiFi.persistent(false);  // don't write the hotspot to flash on every wake-up
  WiFi.mode(WIFI_STA);
  WiFi.begin(inst.hotspotNaam, inst.hotspotWachtwoord);
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

// ---- Pairing: the box's own network, for the app or a browser ----

static WebServer server(80);
static bool nieuwGekoppeld = false;

static String netwerkNaam() {
  const uint64_t mac = ESP.getEfuseMac();
  char naam[20];
  snprintf(naam, sizeof naam, "Veldsensor-%02X%02X", (unsigned)((mac >> 32) & 0xFF), (unsigned)((mac >> 40) & 0xFF));
  return String(naam);
}

static bool alleen(const String &s, const char *toegestaan) {
  for (size_t i = 0; i < s.length(); i++) {
    if (!strchr(toegestaan, s[i])) return false;
  }
  return true;
}

// Escapes text for HTML, so a hotspot name cannot break the page.
static String html(const char *s) {
  String uit;
  for (; *s; s++) {
    switch (*s) {
      case '&': uit += "&amp;"; break;
      case '<': uit += "&lt;"; break;
      case '>': uit += "&gt;"; break;
      case '"': uit += "&quot;"; break;
      default: uit += *s;
    }
  }
  return uit;
}

static void stuurPagina() {
  String pagina;
  pagina.reserve(2400);
  pagina += F("<!doctype html><html lang=nl><head><meta charset=utf-8><meta name=viewport content='width=device-width'>"
              "<title>Sensorkastje</title><style>body{font-family:sans-serif;margin:16px;max-width:30em}"
              "label{display:block;margin-top:12px}input{width:100%;font-size:1.1em;padding:6px;box-sizing:border-box}"
              "button{margin-top:16px;font-size:1.1em;padding:10px}</style></head><body>");
  pagina += "<h1>Sensorkastje</h1><p>Nu: ruw " + String(leesSensor()) + " (hoger = droger).</p>";
  pagina += F("<p>Makkelijker: open de Veldvlucht-app, <i>Sensoren</i>, <i>Kastje koppelen</i>.</p>"
              "<form method=post action=/instellingen><input type=hidden name=vanuit value=pagina>");
  pagina += "<label>Naam van je hotspot<input name=hotspot maxlength=32 value=\"" + html(inst.hotspotNaam) + "\"></label>";
  pagina += F("<label>Wachtwoord van je hotspot (leeg = hetzelfde als eerst)<input name=wachtwoord type=password maxlength=63></label>");
  pagina += "<label>Naam van de sensor<input name=sensor maxlength=40 value=\"" + html(inst.sensorId) + "\"></label>";
  pagina += "<label>Sleutel van de sensor<input name=sleutel maxlength=64 value=\"" + html(inst.sensorSleutel) + "\"></label>";
  pagina += "<label>Cloudproject (leeg = alleen naar de app)<input name=project maxlength=40 value=\"" + html(inst.cloudProject) + "\"></label>";
  pagina += "<label>Cloudsleutel<input name=cloudsleutel maxlength=256 value=\"" + html(inst.cloudSleutel) + "\"></label>";
  pagina += "<label>Diepte in cm<input name=diepte type=number value=" + String(inst.diepteCm) + "></label>";
  pagina += "<label>Om de hoeveel minuten meten<input name=interval type=number value=" + String(inst.intervalMinuten) + "></label>";
  pagina += F("<button>Bewaren</button></form></body></html>");
  server.send(200, "text/html; charset=utf-8", pagina);
}

// The answer: JSON for the app, a page for a browser.
static void antwoord(bool vanuitPagina, int code, bool ok, const String &tekst, uint16_t ruw) {
  if (vanuitPagina) {
    server.send(code, "text/html; charset=utf-8",
                "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><body style='font-family:sans-serif'><h1>"
                + String(ok ? "Gekoppeld" : "Niet bewaard") + "</h1><p>" + tekst + "</p>" + (ok ? "" : "<p><a href=/>Terug</a></p>"));
    return;
  }
  String json = String("{\"ok\":") + (ok ? "true" : "false");
  if (ok) {
    json += ",\"sensorId\":";
    voegJsonTekstToe(json, inst.sensorId);
    json += ",\"ruw\":" + String(ruw);
  } else {
    json += ",\"fout\":";
    voegJsonTekstToe(json, tekst.c_str());
  }
  json += "}";
  server.send(code, "application/json", json);
}

static void ontvangInstellingen() {
  const bool vanuitPagina = server.arg("vanuit") == "pagina";
  Instellingen n = inst;
  const String hotspot = server.arg("hotspot");
  const String wachtwoord = server.arg("wachtwoord");
  const String sensor = server.arg("sensor");
  const String sleutel = server.arg("sleutel");
  const String project = server.arg("project");
  const String cloudsleutel = server.arg("cloudsleutel");
  const long diepte = server.hasArg("diepte") ? server.arg("diepte").toInt() : n.diepteCm;
  const long interval = server.hasArg("interval") ? server.arg("interval").toInt() : n.intervalMinuten;

  const char *fout = nullptr;
  if (hotspot.isEmpty() || hotspot.length() > 32) fout = "De naam van de hotspot moet 1 tot 32 tekens zijn.";
  else if (!wachtwoord.isEmpty() && (wachtwoord.length() < 8 || wachtwoord.length() > 63)) fout = "Het wachtwoord van de hotspot moet 8 tot 63 tekens zijn.";
  else if (wachtwoord.isEmpty() && hotspot != inst.hotspotNaam) fout = "Vul het wachtwoord van de hotspot in.";
  else if (sensor.isEmpty() || sensor.length() > 40 || !alleen(sensor, "abcdefghijklmnopqrstuvwxyz0123456789-")) fout = "De naam van de sensor mag alleen kleine letters, cijfers en streepjes hebben.";
  else if (sleutel.length() > 64 || project.length() > 40 || cloudsleutel.length() > 256) fout = "Een sleutel of het cloudproject is te lang.";
  else if (!alleen(project, "abcdefghijklmnopqrstuvwxyz0123456789")) fout = "Het cloudproject mag alleen kleine letters en cijfers hebben.";
  else if (!project.isEmpty() && (sleutel.isEmpty() || cloudsleutel.isEmpty())) fout = "Met een cloudproject zijn ook de sleutel van de sensor en de cloudsleutel nodig.";
  else if (diepte < 0 || diepte > 200) fout = "De diepte moet 0 tot 200 cm zijn.";
  else if (interval < 1 || interval > 1440) fout = "Meten kan elke 1 tot 1440 minuten.";
  if (fout) {
    Serial.printf("Koppelen niet gelukt: %s\n", fout);
    antwoord(vanuitPagina, 400, false, fout, 0);
    return;
  }

  strlcpy(n.hotspotNaam, hotspot.c_str(), sizeof n.hotspotNaam);
  if (!wachtwoord.isEmpty()) strlcpy(n.hotspotWachtwoord, wachtwoord.c_str(), sizeof n.hotspotWachtwoord);
  strlcpy(n.sensorId, sensor.c_str(), sizeof n.sensorId);
  strlcpy(n.sensorSleutel, sleutel.c_str(), sizeof n.sensorSleutel);
  strlcpy(n.cloudProject, project.c_str(), sizeof n.cloudProject);
  strlcpy(n.cloudSleutel, cloudsleutel.c_str(), sizeof n.cloudSleutel);
  n.diepteCm = (uint16_t)diepte;
  n.intervalMinuten = (uint16_t)interval;
  if (!bewaarInstellingen(n)) {
    antwoord(vanuitPagina, 500, false, "Bewaren in het geheugen van het kastje lukte niet. Probeer het opnieuw.", 0);
    return;
  }
  if (strcmp(n.sensorId, inst.sensorId) != 0) {
    // Another sensor: measurements of the old one must not be sent under the new name.
    bewaardBegin = 0;
    bewaardAantal = 0;
  }
  inst = n;
  nieuwGekoppeld = true;
  const uint16_t ruw = leesSensor();
  Serial.printf("Gekoppeld als sensor %s, hotspot \"%s\"%s. Nu: ruw %u.\n", inst.sensorId, inst.hotspotNaam,
                inst.cloudProject[0] ? ", met de cloud" : ", alleen naar de app", (unsigned)ruw);
  antwoord(vanuitPagina, 200, true,
           "Het kastje is nu sensor " + html(inst.sensorId) + " en meet ruw " + String(ruw) + ". Zet je hotspot aan; het kastje stuurt zo zijn eerste meting.",
           ruw);
}

// The box's own network: two minutes after switching on, or until it has settings.
static void koppelModus() {
  const bool totGekoppeld = !gekoppeld();
  const String naam = netwerkNaam();
  WiFi.mode(WIFI_AP);
  WiFi.softAP(naam.c_str(), KOPPEL_WACHTWOORD);
  server.on("/", HTTP_GET, stuurPagina);
  server.on("/instellingen", HTTP_POST, ontvangInstellingen);
  server.on("/meting", HTTP_GET, [] {
    String json = "{\"sensorId\":";
    voegJsonTekstToe(json, inst.sensorId);
    json += ",\"ruw\":" + String(leesSensor()) + "}";
    server.send(200, "application/json", json);
  });
  server.onNotFound([] {
    server.sendHeader("Location", "http://192.168.4.1/");
    server.send(302, "text/plain", "");
  });
  server.begin();
  Serial.printf("Koppelen: verbind je iPhone met wifi \"%s\" (wachtwoord %s) en kies in de app Kastje koppelen.\n",
                naam.c_str(), KOPPEL_WACHTWOORD);
  Serial.println(totGekoppeld ? "Het kastje heeft nog geen instellingen: het netwerk blijft aan tot het gekoppeld is."
                              : "Het netwerk blijft 2 minuten aan; daarna gaat het kastje meten.");

  const uint32_t start = millis();
  uint32_t herinnering = start;
  while (!nieuwGekoppeld && (totGekoppeld || millis() - start < KOPPEL_MS)) {
    server.handleClient();
    if (millis() - herinnering > 30000) {
      herinnering = millis();
      Serial.printf("Wacht op koppelen via wifi \"%s\" ...\n", naam.c_str());
    }
    delay(2);
  }
  // Let the answer reach the iPhone before the network goes away.
  const uint32_t klaar = millis();
  while (nieuwGekoppeld && millis() - klaar < 1500) {
    server.handleClient();
    delay(2);
  }
  server.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  Serial.println(nieuwGekoppeld ? "Koppelnetwerk uit." : "Niet gekoppeld; de oude instellingen blijven. Koppelnetwerk uit.");
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
  // Subtract the time awake, so measurements stay about one interval apart.
  const uint64_t intervalUs = (uint64_t)inst.intervalMinuten * 60ULL * 1000000ULL;
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

  laadInstellingen();

  Serial.println();
  Serial.printf("=== Sensorkastje %s ===\n", gekoppeld() ? inst.sensorId : "(nog niet gekoppeld)");
  const esp_sleep_wakeup_cause_t oorzaak = esp_sleep_get_wakeup_cause();
  if (oorzaak == ESP_SLEEP_WAKEUP_TIMER) {
    Serial.println("Wakker na het slapen.");
  } else if (oorzaak == ESP_SLEEP_WAKEUP_EXT0) {
    Serial.println("BOOT-knop ingedrukt: nu meten en versturen.");
  } else {
    Serial.println("Opgestart (stroom aan, resetknop of nieuwe upload).");
  }
  if (oorzaak != ESP_SLEEP_WAKEUP_TIMER && oorzaak != ESP_SLEEP_WAKEUP_EXT0) {
    koppelModus();
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
