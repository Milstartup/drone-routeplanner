// Voorbeeld voor Instellingen.h. Niet meer nodig als je het kastje koppelt met
// de app (sensor/README.md, "Koppelen met de app"); alleen voor de testmodus of
// andere pinnen. Kopieer dit bestand dan naar Instellingen.h (in dezelfde map)
// en vul daar je eigen waarden in. Instellingen.h staat in .gitignore en komt
// dus nooit in git. Zet in DIT voorbeeldbestand nooit je echte wachtwoord.
// Wat de app bij het koppelen stuurt, gaat voor wat hier staat.

#pragma once

// ---- Hotspot van je iPhone ----

// De naam van de hotspot is de naam van je iPhone, precies zoals in
// Instellingen -> Algemeen -> Info -> Naam. Let op hoofdletters en spaties.
#define HOTSPOT_NAAM ""

// Het wachtwoord staat in Instellingen -> Persoonlijke hotspot.
#define HOTSPOT_WACHTWOORD ""

// ---- Het centrale systeem in de cloud (centraal/README.md) ----

// Laat deze drie leeg als het kastje alleen naar de app moet sturen.
// Met deze drie stuurt het kastje via de hotspot rechtstreeks naar de cloud;
// de app hoeft dan niet open te zijn. Lukt de cloud niet, dan probeert het de app.

// De letters voor .supabase.co. In de app: Route -> Account -> CLOUD_PROJECT.
#define CLOUD_PROJECT ""

// De publishable key van het project. In de app: Route -> Account -> CLOUD_SLEUTEL.
#define CLOUD_SLEUTEL ""

// De sleutel van deze ene sensor. In de app: Veldkaart -> Sensoren plaatsen en ijken.
// Geheim: wie deze sleutel heeft, kan metingen voor deze sensor sturen.
#define SENSOR_SLEUTEL ""

// ---- Sensor ----

// De naam van deze sensor. De Veldvlucht-app laat zien wat je hier invult.
// Gebruik alleen kleine letters, cijfers en streepjes.
#define SENSOR_ID "mijn-veld-s1"

// Hoe diep de meetvork in de grond zit, in centimeters.
#define DIEPTE_CM 15

// Om de hoeveel minuten het kastje meet (en probeert te versturen).
#define MEET_INTERVAL_MINUTEN 60

// true = testen op tafel: elke 10 seconden meten, zonder te slapen.
// Zet dit terug op false voordat het kastje het veld in gaat.
#define TESTMODUS false

// ---- Aansluitingen (GPIO-nummers op het ESP32-bordje) ----

// Naar VCC van het sensorprintje. Het kastje zet de sensor alleen aan
// tijdens een meting, zodat de metalen pootjes minder slijten.
#define SENSOR_VOEDING_PIN 25

// Naar AO (analoog) van het sensorprintje. Moet GPIO 32 t/m 39 zijn,
// want de andere analoge pinnen werken niet als de wifi aan staat.
#define SENSOR_PIN 34

// Batterijspanning meten via twee weerstanden (een spanningsdeler).
// -1 = niet aangesloten. Anders GPIO 32 t/m 39, bijvoorbeeld 35.
#define BATTERIJ_PIN -1

// Hoeveel keer de batterijspanning groter is dan de spanning op de pin.
// Twee gelijke weerstanden (bijvoorbeeld 2 x 100 kilo-ohm) = 2.0.
#define BATTERIJ_DELER 2.0
