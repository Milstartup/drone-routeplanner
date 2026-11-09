# Architectuur: drone, sensoren, weer en centraal systeem

Vastgelegd op 25 oktober 2026, bijgewerkt op 27 oktober 2026. Gebouwd zijn:

- de routeplanner;
- de iPhone-app;
- de software voor het sensorkastje;
- het centrale systeem in de cloud (Supabase), met accounts, delen en een eerste foto-analyse;
- een leer-systeem voor een eigen AI, op de Mac. Die AI is nog niet getraind: daarvoor zijn foto's van je eigen veld nodig.
 Wat nog niet met echte apparaten getest is, staat in [TESTLIJST.md](TESTLIJST.md).

## Doel

Eén systeem dat per broccoliveld drie bronnen samenbrengt:

- de foto's van de drone;
- de metingen van bodemvochtsensoren in het veld;
- de weersverwachting.

Een AI in het centrale systeem bepaalt daaruit **hoeveel water welke delen van het veld nodig hebben**, en **markeert planten of plekken die aandacht nodig hebben**. Alles is overzichtelijk te zien op een **veldkaart in de iPhone-app**.

## Overzicht

```
 VELD                                  CENTRAAL SYSTEEM (Supabase)                IPHONE-APP
 ────                                  ───────────────────────────                ──────────
 Sensorkastjes ──hotspot iPhone──►  ┐
   (sensor + microcontroller +       │   1. Ontvangen en opslaan per veld          Vlucht-scherm
    accu + zonnepaneel)              │      (metingen, foto's, fotolog, weer)        (drone, los van de rest)
                                     ├─► 2. Wateradvies per zone (regels → AI)
 Drone ──foto's + fotolog────────►   │   3. Planten/plekken markeren (AI op foto's) Veldkaart-scherm
   (via de iPhone-app, na de vlucht) │   4. Resultaten klaarzetten als kaartlagen ─► (zones, markeringen,
                                     │                                               sensoren, weer)
 Weerdienst (API) ───────────────►   ┘
```

| Onderdeel | Status | Waar |
|---|---|---|
| Routeplanner | **Klaar** (prototype) | Deze repository, `src/` |
| Drone-app (vliegen + foto's) | Haalbaarheidstest **geslaagd** met de drone (26 oktober 2026). Route inlezen en **vliegen in de DJI-simulator** gebouwd, getest met een nep-drone. Echt vliegen nog niet. | [`ios/`](../ios/README.md), [DJI-MOBILE-SDK-V4.md](DJI-MOBILE-SDK-V4.md), [STAPPENPLAN.md](STAPPENPLAN.md) |
| Veld tekenen in de app | **Gebouwd** (26 oktober 2026): hoeken aantikken, de app maakt de route op dezelfde manier als de planner | [`ios/`](../ios/README.md) |
| Sensorkastje | Software **gebouwd**, nog niet getest met een echt bordje | [`sensor/`](../sensor/README.md), dit document, hoofdstuk 2 |
| Centraal systeem | **Gebouwd in de cloud** (27 oktober 2026): ontvangen, opslaan, weer en wateradvies elk uur, accounts en delen. De foto-analyse draait op de Mac (eenvoudige regels, geen getrainde AI). Nog te installeren in je eigen Supabase-project. | [`centraal/`](../centraal/README.md), dit document, hoofdstuk 4 |
| Veldkaart in de iPhone-app | **Gebouwd**: je eigen veld met sensoren, weer en advies, of de voorbeeldgegevens | [`ios/`](../ios/README.md), dit document, hoofdstuk 5 |

## Scheidingsregels

Elk onderdeel heeft één taak en praat met de andere alleen via vastgelegde dataformaten (hoofdstuk 6):

- **De routeplanner** plant alleen. `src/core` bevat geen UI-, drone-, sensor- of AI-code; `separation.test.ts` bewaakt dat.
- **Het vluchtdeel van de iPhone-app** doet alleen vliegen en foto's maken. Tijdens een vlucht staan er geen sensor- of AI-schermen in de weg.
- **De sensorkastjes** meten en versturen alleen. Ze nemen geen beslissingen.
- **Het centrale systeem** is de enige plek waar gegevens worden gecombineerd en waar de AI draait.
  - **Het draait in de cloud**, in Supabase: [`centraal/`](../centraal/README.md).
  - **De foto-analyse draait op de Mac**, omdat de foto's te groot zijn voor de gratis cloud. Alleen de gevonden plekken gaan naar de cloud.
  - **De app heeft een reserve:** dezelfde regels voor het wateradvies (`WaterAdvisor` in `ios/VeldvluchtKern`). Die gebruikt de app als je niet bent ingelogd, of als de app nieuwere metingen heeft dan de cloud. Zo werkt hij ook zonder internet in het veld.
- **De veldkaart** toont alleen wat het centrale systeem klaarzet. Het scherm zelf rekent geen advies uit.

## 1. Drone en foto's

- Het vliegen en het fotograferen werken zoals beschreven in [STAPPENPLAN.md](STAPPENPLAN.md): de app maakt een losse foto op elke geplande fotopositie.
- Na de vlucht gaan de foto's (van de microSD-kaart) plus het **fotolog** van de app naar het centrale systeem.
- **Wat de camera kan:** de Mavic Mini heeft een gewone kleurencamera (RGB, 12 MP). Op 30 m is dat ongeveer 1,1 cm per pixel, dus losse broccoliplanten zijn goed te zien. De app draait de camera vóór het opstijgen recht naar beneden (−90°) en zet hem tijdens de route terug als hij scheef staat.
- **Wat de camera niet kan:** hij ziet wat het oog ziet, dus vergeling, slappe of achterblijvende planten en kale plekken. Watertekort dat nog niet zichtbaar is, ziet hij niet; daarvoor zijn warmte- of multispectrale camera's nodig.
- **Gevolg voor het wateradvies:** dat steunt dus vooral op de sensoren en het weer. De foto's laten zien **waar** het slechter gaat.
- **Plaatsnauwkeurigheid:** de Mini houdt zijn positie volgens DJI op ongeveer ±1,5 m (met GPS). Een markering op de kaart ligt daardoor naar schatting binnen 1 à 2 m van de echte plant. Dat moet bij de eerste vluchten gecontroleerd worden.

## 2. Bodemvochtsensoren

**De huidige sensor** is de bodemvochtigheidsmeter (analoog/digitaal) van Bits & Parts, €1,50. Zo werkt hij:

- meetvork van 60 × 30 mm, printje met een LM393-chip;
- voeding 3,3–5 V;
- uitgangen: analoog (AO, de mate van vocht) en digitaal (DO, aan/uit via een instelschroefje);
- geen draadloze verbinding: er is een microcontroller nodig om hem uit te lezen.

**Een sensorkastje** bestaat uit:

- de sensor (in de grond, op de diepte van de wortels);
- een microcontroller, bijvoorbeeld een ESP32-bordje. Voor LoRaWAN neem je een bordje met een LoRa-chip. Lees de **analoge** uitgang uit, niet de digitale;
- een accu, eventueel met een klein zonnepaneel;
- een waterdicht kastje;
- een vaste, bekende GPS-positie per sensor.

**Versturen (gebouwd, 26 en 27 oktober 2026).** Het kastje stuurt zijn metingen via de **hotspot van de iPhone**:
- Het kastje meet elk uur en bewaart de metingen.
- Ziet het de hotspot, dan stuurt het alles in het formaat `veld/sensorupload` (hoofdstuk 6):
  - **eerst naar de cloud**, via het internet van de hotspot, met de geheime sleutel van zijn sensor. De app hoeft dan niet open te zijn;
  - lukt dat niet, **naar de app** op de iPhone. De app moet dan open zijn, en stuurt de metingen later zelf door naar de cloud.
- Een meting die twee keer aankomt, telt maar één keer.
- Hoe je het kastje bouwt, staat in [`sensor/README.md`](../sensor/README.md).

**Andere manieren voor later.** Op een akker is meestal geen wifi. De opties:

- **LoRaWAN**, bijvoorbeeld via The Things Network: weinig stroom en een groot bereik. Controleer de dekkingskaart voor je veld.
- **Mobiel netwerk** (NB-IoT of LTE-M), met een simkaart per kastje.
- **Wifi**, alleen als het veld dicht bij een gebouw met wifi ligt.

**Belangrijke beperkingen van deze sensor:**

- **Slijtage.** Het lijkt het bekende type met twee blote metalen pootjes; de productpagina zegt dat niet letterlijk, maar de vorm en de chip wijzen erop. Zulke pootjes slijten en roesten snel in vochtige grond, zeker als er continu stroom op staat. Zet de sensor daarom **alleen aan tijdens een meting**: de microcontroller schakelt de voeding even in, meet en schakelt weer uit.
- **IJken.** Het getal is een ruwe waarde, geen vochtpercentage. IJk het per grondsoort, bijvoorbeeld met een droog en een verzadigd monster van dezelfde grond.
- **Eén plek.** Eén sensor meet één plek. Voor advies per zone is minstens één sensor per zone nodig.
- **Advies:** gebruik deze sensor om te leren en te testen. Kies voor echte beslissingen **capacitieve sensoren** (zonder blote metalen pootjes) of landbouwsensoren met LoRaWAN.

## 3. Weer

Een app of server mag de weersverwachting uit de Google-zoekresultaten niet zomaar uitlezen. Gebruik een officiële weerdienst met een API:

| Dienst | Voorwaarden (stand oktober 2026, controleer voor gebruik) |
|---|---|
| **KNMI Data Platform** | Officieel Nederlands. Gratis API-sleutel via het ontwikkelaarsportaal; licentie per dataset, vaak CC BY 4.0. |
| **Google Weather API** (Google Maps Platform) | API-sleutel en betaalgegevens nodig, met een gratis tegoed per maand. |
| **Open-Meteo** | Gratis alleen voor niet-commercieel gebruik; voor commercieel gebruik een betaald abonnement. Bronvermelding verplicht (CC BY 4.0). |

- **Wat het systeem nodig heeft:** de verwachte neerslag (mm), temperatuur, wind en eventueel verdamping voor de komende dagen.
- **Ook voor het vliegen:** het weer is nuttig om vluchten te plannen, want de Mavic Mini kan wind tot 8 m/s aan.

## 4. Centraal systeem

**Taken:**

1. **Ontvangen en opslaan per veld:** sensormetingen, foto's met fotolog, weersverwachtingen en de veldgrens (uit het routebestand).
2. **Wateradvies per zone:**
   - **Begin met eenvoudige, controleerbare regels**, bijvoorbeeld: "vochtwaarde onder de grens én minder dan X mm regen verwacht → water geven".
   - **Gebruik pas AI als er genoeg gegevens zijn** om haar mee te trainen en te controleren.
3. **Planten of plekken markeren:** een AI-model op de drone-foto's herkent zichtbare problemen. Zo'n model moet getraind worden met voorbeeldfoto's waarvan bekend is wat er aan de hand is (gelabelde foto's). Die verzamel je bij de eerste vluchten.
4. **Resultaten klaarzetten** als kaartlagen voor de app (zie hoofdstuk 6).

**Gebouwd (26 en 27 oktober 2026).** Het draait in **Supabase**, een gratis clouddienst met een database (Postgres), inloggen en kleine programma's in de cloud. Alles staat in [`centraal/`](../centraal/README.md).

1. **Ontvangen en opslaan**, in tabellen per veld:
   - `velden`: de veldgrens, de vliegbanen en de sensoren, met de eigenaar;
   - `sensoren`: elke sensor met zijn geheime sleutel voor het kastje;
   - `sensormetingen`: alle ruwe metingen, ook van vroeger;
   - `weer`, `vluchten` (de fotologs), `aandacht` (de plekken uit de foto-analyse) en `resultaten` (het advies voor de veldkaart).
2. **Wie wat mag zien** (*row level security* in de database):
   - je ziet alleen je eigen velden, en de velden die iemand met je deelt (`veld_leden`);
   - alleen de eigenaar verandert iets, en alleen de eigenaar ziet de sleutels van de kastjes;
   - een kastje kan alleen metingen toevoegen, voor zijn eigen sensor (`sensor_upload`).
3. **Weer:** de verwachting voor vijf dagen van Open-Meteo, met de vliegmomenten. Elk uur opnieuw.
4. **Wateradvies per strook** met eenvoudige regels. Het programma `centraal` (een *edge function*) rekent elk uur, en meteen na nieuwe metingen of een veranderd veld. De regels:
   - De stroken lopen langs de vliegbanen. Dat is ook de rijrichting van de tractor. Ze zijn standaard 24 m breed.
   - Per strook telt de sensor in die strook, of anders een sensor die ernaast ligt.
   - De sensor moet geijkt zijn, en de meting mag niet ouder zijn dan 2 dagen. Anders komt er geen advies, met de reden erbij.
   - **Droger dan 35 %:**
     - komt er de komende 2 dagen minder dan 10 mm regen → **nu water geven**;
     - komt er 10 mm of meer → **binnenkort**: wacht op de regen.
   - **Tussen 35 en 50 %:**
     - minder dan 5 mm meer regen dan verdamping → **binnenkort water geven**;
     - anders → **genoeg**.
   - **50 % of natter:** **genoeg**.
   - De hoeveelheid is ruwweg 0,4 mm per procent tot 55 %.
   - De zekerheid is laag (20 tot 80 %): dit zijn eerste regels, die nog met het veld vergeleken moeten worden.
   - Dezelfde regels staan in de app (`WaterAdvisor`). De tests controleren dat de cloud en de app hetzelfde advies geven, met dezelfde uitleg.
5. **Foto-analyse op de Mac** (`foto-analyse`, niveau 1 van hoofdstuk 7): planten zoeken, de afwijkende markeren, hun plek op de grond uitrekenen. De plekken gaan naar de tabel `aandacht` en staan dan op de veldkaart.
6. **Accounts en delen:** inloggen met e-mail en wachtwoord. De eigenaar nodigt anderen uit om mee te kijken.
7. **Nog niet:** een getrainde AI, en terugkijken naar eerdere dagen in de app. De ruwe metingen worden wel allemaal bewaard.

**Uitgangspunten:**

- **Advies, geen opdracht.** De AI geeft advies. De teler beslist en controleert; de app laat bij elk advies zien waarop het gebaseerd is.
- **Bewaar ruwe gegevens altijd**, zodat je later met betere regels of modellen opnieuw kunt rekenen.
- **Waar het draait:** in Supabase (gekozen op 27 oktober 2026). Gratis, met een database, inloggen en kleine programma's in één dienst. Een project zonder activiteit wordt na 7 dagen gepauzeerd; zie [`centraal/README.md`](../centraal/README.md).

## 5. Veldkaart in de iPhone-app

Eén scherm per veld, overzichtelijk te gebruiken in het veld.

- **Kaart:**
  - luchtfoto als ondergrond (PDOK in Nederland);
  - de veldgrens;
  - de zones, gekleurd naar wateradvies (bijvoorbeeld: blauw = genoeg, geel = binnenkort, rood = nu water geven).
- **Markeringen:** punten voor planten of plekken die aandacht nodig hebben. Tik erop voor de reden en de drone-foto van die plek.
- **Sensoren:** punten met de laatste meting en hoe oud die is. Tik erop voor het verloop van de afgelopen dagen.
- **Weer:** een balk met de verwachting voor de komende dagen.
- **Datum:** terugkijken naar eerdere vluchten en adviezen.
- **Bouwvolgorde:** bouw dit scherm eerst met **voorbeeldgegevens** in de formaten van hoofdstuk 6. Dan is het al te zien en te testen voordat het centrale systeem en de AI bestaan.

## 6. Dataformaten (voorstel versie 0)

Alle coördinaten in WGS84 (decimale graden) en alle tijden in ISO 8601 met tijdzone. Elk formaat krijgt een `format` en een `version`, net als het routebestand.

- **Voorbeeldbestanden** van elk formaat staan in [`voorbeelden/`](voorbeelden/), allemaal voor hetzelfde voorbeeldveld `veld-noord`. De iPhone-app gebruikt ze voor de veldkaart, en de tests in `ios/VeldvluchtKern` controleren ze.
- **Zomertijd:** tot 25 oktober 2026 03:00 is het in Nederland `+02:00`, daarna `+01:00`. Een meting op 25 oktober om 06:00 is dus `2026-10-25T06:00:00+01:00`.

### Sensormeting

```json
{
  "format": "veld/sensormeting",
  "version": 0,
  "sensorId": "veld-noord-s1",
  "fieldId": "veld-noord",
  "location": { "lat": 52.4991, "lng": 5.5431 },
  "depthCm": 15,
  "time": "2026-10-25T06:00:00+01:00",
  "raw": 612,
  "moisturePercent": null,
  "calibration": null,
  "batteryVolt": 3.9
}
```

- `raw` is de ruwe sensorwaarde. Bij de school-sensor betekent een hogere waarde meestal droger.
- `moisturePercent` en `calibration` blijven leeg tot de sensor geijkt is. Bij het ijken in de app vul je de ruwe waarde in droge en in natte grond in; de app rekent dan `moisturePercent` uit.
- Na het ijken: `"calibration": { "dryRaw": 860, "wetRaw": 340 }`, de ruwe waarden in droge en in verzadigde grond van het veld. Het centrale systeem rekent dan `moisturePercent` uit.
- Meerdere metingen in één bestand: een JSON-lijst van zulke objecten (zie [`voorbeelden/voorbeeld-sensormetingen.json`](voorbeelden/voorbeeld-sensormetingen.json)).

### Upload van een sensorkastje

Nieuw op 26 oktober 2026. Zo stuurt een kastje zijn metingen:

- **naar de cloud:** `POST https://<project>.supabase.co/rest/v1/rpc/sensor_upload`, met de publishable key in de kop `apikey` en als inhoud `{"p_sleutel": "<sleutel van de sensor>", "p_upload": <de upload hieronder>}`;
- **of naar de app:** `POST /sensormetingen` op poort 8787 van de iPhone, via zijn hotspot.

De upload zelf:

```json
{
  "format": "veld/sensorupload",
  "version": 0,
  "sensorId": "broccoli-west-s1",
  "depthCm": 15,
  "boot": 1840023117,
  "measurements": [
    { "nr": 41, "ageS": 7200, "raw": 2875, "batteryVolt": 3.91 },
    { "nr": 42, "ageS": 3600, "raw": 2890, "batteryVolt": null }
  ]
}
```

- Het kastje heeft geen klok. `ageS` zegt hoeveel seconden geleden de meting was. De app maakt daar een tijd van.
- `boot` is een willekeurig nummer van de laatste keer dat het kastje aanging, en `nr` telt de metingen sinds dan. Stuurt het kastje metingen nog eens (omdat het het antwoord miste), dan slaan de app en de cloud die over. Beide zijn optioneel.
- De plek (`location`) en het veld (`fieldId`) komen uit de app: daar plaats je de sensor met dezelfde `sensorId`.
- De app antwoordt `200` met `{"ontvangen": 2}`, de cloud met `{"ontvangen": 2, "nieuw": 2}`. Pas dan gooit het kastje de metingen weg.
  - Kent de app de sensor niet (`404`), dan houdt het kastje ze.
  - Klopt de sleutel niet, dan weigert de cloud (`401` of `403`) en probeert het kastje de app.
- De app slaat de metingen op als `veld/sensormeting` (hierboven).

### Fotolog (per vlucht)

```json
{
  "format": "veld/fotolog",
  "version": 0,
  "flightId": "2026-10-25-veld-noord-1",
  "fieldId": "veld-noord",
  "routePlanName": "Broccoli noord",
  "photos": [
    {
      "index": 0,
      "plannedPhotoIndex": 0,
      "file": "DJI_0001.JPG",
      "time": "2026-10-25T10:14:03+01:00",
      "lat": 52.49912,
      "lng": 5.54268,
      "altitudeM": 30,
      "headingDeg": 177
    }
  ]
}
```

- `plannedPhotoIndex` verwijst naar `derived.photoPoints` in het routebestand.
- `file` is de bestandsnaam op de microSD-kaart.

### Resultaten (GeoJSON, voor de veldkaart)

```json
{
  "type": "FeatureCollection",
  "properties": { "format": "veld/resultaten", "version": 0, "fieldId": "veld-noord", "createdAt": "2026-10-25T12:00:00+01:00" },
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Polygon", "coordinates": [[[5.5410, 52.4980], [5.5440, 52.4980], [5.5440, 52.5000], [5.5410, 52.5000], [5.5410, 52.4980]]] },
      "properties": { "kind": "waterzone", "advice": "water", "amountMm": 12, "reason": "Sensor s1 droog, geen regen verwacht", "confidence": 0.7 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [5.5425, 52.4991] },
      "properties": { "kind": "aandacht", "reason": "Plant duidelijk geler dan omgeving", "photoFile": "DJI_0042.JPG", "flightId": "2026-10-25-veld-noord-1", "confidence": 0.6 }
    }
  ]
}
```

GeoJSON zet de lengtegraad **vóór** de breedtegraad (`[lng, lat]`), anders dan de andere formaten.

Soorten (`kind`):

| `kind` | Geometrie | Velden |
|---|---|---|
| `veldgrens` | Polygon | `name` |
| `waterzone` | Polygon (een strook langs de rijrichting van de tractor) | `name`, `advice` (`genoeg`, `binnenkort` of `water`), `amountMm`, `reason`, `confidence` (0 tot 1) |
| `aandacht` | Point | `reason`, `photoFile`, `flightId`, `confidence` |

- **Elk advies en elke markering heeft een `reason`.** De app laat altijd zien waarop het gebaseerd is.
- **Kleuren op de veldkaart:** `genoeg` blauw, `binnenkort` geel, `water` rood.

### Weer (voor de veldkaart)

Nieuw in dit voorstel. Het centrale systeem haalt de verwachting op bij een weerdienst (hoofdstuk 3) en zet ze in dit formaat klaar, met de vliegmomenten uit hoofdstuk 7. In versie 0 haalt de app de verwachting zelf op bij Open-Meteo, voor het midden van het veld.

```json
{
  "format": "veld/weer",
  "version": 0,
  "fieldId": "veld-noord",
  "location": { "lat": 52.499, "lng": 5.5425 },
  "source": "Open-Meteo",
  "attribution": "Weergegevens door Open-Meteo.com (CC BY 4.0)",
  "createdAt": "2026-10-25T12:00:00+01:00",
  "days": [
    { "date": "2026-10-27", "precipitationMm": 0.2, "tempMinC": 5, "tempMaxC": 12, "windMaxMps": 3.4, "gustMaxMps": 6.1, "evaporationMm": 0.6 }
  ],
  "flightWindows": [
    { "start": "2026-10-27T11:00:00+01:00", "end": "2026-10-27T15:00:00+01:00", "reason": "Wind 3 m/s met windstoten tot 6 m/s, droog en daglicht." }
  ]
}
```

- `date` is de dag in Nederlandse tijd. Wind in m/s, omdat de grens van de Mavic Mini ook in m/s staat (8 m/s).
- `attribution` is de verplichte bronvermelding van de weerdienst; de app toont die bij het weer.
- `flightWindows` mag leeg zijn als er geen goed vliegmoment is.

## 7. Eisen (antwoorden van 25 oktober 2026)

**Soort project.** Het is een **schoolproject**: een concept op kleine schaal, zonder budget en niet commercieel. In theorie moet het wel te gebruiken zijn op een groot veld.

### Veld en sensoren

| Eis | Gevolg voor het ontwerp |
|---|---|
| Veld, plek en grootte zelf te kiezen in de app | Kan in de routeplanner, en **sinds 26 oktober 2026 ook in de app zelf**: tik de hoeken aan, de app maakt de vliegbanen. |
| Aantal bodemvochtsensoren zelf te kiezen | "Sensoren plaatsen" in de app (*gebouwd*): kies een aantal, de app stelt een gelijkmatige verdeling over het veld voor, en de punten zijn te verslepen. Elke sensor krijgt een id en een vaste positie (`sensorId`, `location`). |
| De school-sensor van €1,50 wordt gebruikt | Prima voor het concept. Houd rekening met slijtage en ijken (hoofdstuk 2). Er wordt zelf gebouwd met een ESP32. |
| Sensoren versturen via de **hotspot van de telefoon** | De ESP32 maakt verbinding met de hotspot. Omdat die er niet altijd is, **bewaart het kastje zijn metingen** en verstuurt het ze zodra de hotspot in de buurt is. Voor een echt groot veld: LoRaWAN of een simkaart per kastje. |

### Water geven

| Eis | Gevolg voor het ontwerp |
|---|---|
| Een tractor met waterkanonnen rijdt heen en weer, en kan per stuk water geven | Het advies wordt per **strook langs de rijrichting van de tractor**, met de breedte van het bereik van de kanonnen. Later in te stellen: rijrichting, afstand tussen de rijpaden en bereik. De waterzones uit hoofdstuk 6 worden dus stroken. |

### Vliegen

| Eis | Gevolg voor het ontwerp |
|---|---|
| Het systeem geeft aan wanneer je het beste kunt vliegen, met een melding | Het centrale systeem bekijkt de verwachting en zoekt een **vliegmoment**: wind en windstoten ruim onder 8 m/s, geen regen, daglicht. *Gebouwd: minstens 2 uur achter elkaar met wind onder 5 m/s, windstoten onder 7 m/s, droog en licht. De app geeft een melding een uur van tevoren, als je die aanzet.* Een echte pushmelding van een server naar de iPhone vraagt een betaald Apple Developer-lidmaatschap. Gratis alternatieven: de app haalt het advies zelf op en zet een **lokale melding**, of het advies staat bovenaan de veldkaart. |
| Advies na een vlucht: liefst snel, maar het moet kloppen | De analyse draait direct na het uploaden. Eerst komen snelle resultaten (sensoren en weer), daarna die van de foto's. |
| **"Niemand vliegt de drone, hij vliegt zelf"** | De drone vliegt de route zelf: de app stuurt en maakt de foto's. Toch moet er bij elke vlucht iemand aanwezig zijn, om twee redenen. **Technisch:** de Mini heeft geen missies aan boord, dus de afstandsbediening en de iPhone-app moeten de hele vlucht aan staan. **Wettelijk:** in de open categorie van de EU-regels moet er een piloot zijn die de drone ziet en kan ingrijpen. Een drone die volledig zelfstandig vertrekt en landt, is met de Mavic Mini niet mogelijk. |

### Apparaten

| Eis | Gevolg voor het ontwerp |
|---|---|
| iPhone 13 | Lightning-aansluiting; het gemelde probleem met USB-C-iPhones speelt hier niet. |
| MacBook Pro 13-inch 2018 met **Intel-chip**, macOS Sequoia 15.7.4 (geen Tahoe mogelijk); iPhone 13 met iOS 27.0.1 | Gebruik **Xcode 16.4**, met Xcode 26.3 als reserve. Xcode 27 draait niet op Intel. Xcode 26 en 16 wel, afhankelijk van de macOS-versie (zie [STAPPENPLAN.md](STAPPENPLAN.md), stap 0). Voor eigen gebruik is dat genoeg, want de App Store is toch geen optie. Twee voordelen: met Xcode 16 (iOS 18-SDK) speelt de bouwfout met de iOS 26-SDK niet, en de DJI-simulator (alleen voor Intel gebouwd) draait op een Intel-Mac zonder Rosetta. |
| Firmware drone 01.00.0500 | Precies de versie die de iOS-SDK noemt. **Werk de firmware niet bij**, ook niet als DJI Fly erom vraagt. |

### Centraal systeem en AI

| Eis | Gevolg voor het ontwerp |
|---|---|
| Plek maakt niet uit, moet goed bereikbaar zijn vanuit de app | Een gratis clouddienst met database, opslag en inloggen: **Supabase** (gekozen op 27 oktober 2026). |
| Alleen jij, maar je kunt mensen toevoegen | Inloggen met accounts. Per veld is er een eigenaar die anderen kan uitnodigen om mee te kijken. |
| Foto's horen bij de analyse | Eén vlucht over een heel veld kan honderden foto's van een paar MB opleveren, samen gigabytes. Gratis cloudopslag is klein. Daarom **draait de foto-analyse op de laptop**, en gaan alleen de resultaten en kleine voorbeeldfoto's naar de cloud. |
| De AI herkent planten die een inspectie nodig hebben, en planten die meer of minder water nodig hebben | Zie de aanpak hieronder. |
| De AI moet "alles op Google bekijken" | Zo werkt het niet. Foto's en video's van internet mag je niet zomaar gebruiken (auteursrecht). Ze lijken ook niet op luchtfoto's van jouw veld vanaf 30 m. Een AI leert van voorbeelden die lijken op wat hij later moet beoordelen. |

**Aanpak van de analyse, in drie niveaus:**

1. **Zonder getrainde AI (eerst):**
   - De analyse zoekt in de drone-foto's de losse broccoliplanten.
   - Per plant meet hij hoe groen en hoe groot die is.
   - Planten die duidelijk afwijken van hun buren krijgen de markering **"inspectie nodig"**.
   - Dit is uitlegbaar, gratis en werkt zonder voorbeeldfoto's.
   - *Gebouwd op 27 oktober 2026: `foto-analyse` in `ios/VeldvluchtKern`. Getest met nagemaakte foto's, nog niet met echte.*
2. **Wateradvies met een waterbalans per strook:**
   - In: de laatste sensormetingen, de verwachte regen en de verdamping uit de weersverwachting.
   - Uit: per strook "genoeg", "binnenkort" of "nu water geven".
   - De foto's bevestigen het advies: blijven planten in een strook achter of verkleuren ze?
3. **Later een getrainde AI:**
   - Leren van gelabelde foto's: eigen drone-foto's waarbij je in het veld hebt gecontroleerd wat er aan de hand was, aangevuld met openbare datasets met een licentie die dat toelaat.
   - Een bestaande beeld-AI via een API kan ook, maar die kost geld per foto. Dat past niet bij een project zonder budget.
   - *Gebouwd op 9 november 2026, het leer-systeem:*
     - `foto-analyse` knipt elke gemarkeerde plant en een paar gewone planten uit als plaatje van 224 × 224 pixels. De boer sorteert ze in mappen: gezond, te droog, te nat, ziek of beschadigd, geen plant.
     - `foto-analyse leer` laat Create ML daarvan leren (overdrachtsleren op Apples *scene print*, gratis en op de Mac).
     - Daarna vraagt de analyse de AI naar elke plant, één keer per plant.
     - Code: `PlantLearning.swift` en `Sources/FotoAnalyse/Leren.swift`. Getest met nagemaakte foto's; uitleg in [`centraal/README.md`](../centraal/README.md).

**Weer.** Omdat het geen commercieel gebruik is, mag de **gratis Open-Meteo-API** gebruikt worden (geen sleutel, wel bronvermelding). Het KNMI Data Platform kan ook.

**Piloot.** Bevestigd: bij elke vlucht is er iemand als piloot aanwezig die kan ingrijpen.

### Nog open

- **Gegevens van de tractor** voor de stroken: rijrichting, afstand tussen rijpaden en bereik van de kanonnen. Mag later.

## 8. Bouwvolgorde

Deze volgorde staat ook in [STAPPENPLAN.md](STAPPENPLAN.md).

1. **Dataformaten** van hoofdstuk 6 vastleggen, met voorbeeldbestanden. *Gedaan: [`voorbeelden/`](voorbeelden/).*
2. **Veldkaart in de iPhone-app** met voorbeeldgegevens. *Gebouwd in [`ios/`](../ios/README.md); nog te testen in het veld.*
3. **Drone-app:** de haalbaarheidstest, daarna vliegen en foto's. *Haalbaarheidstest geslaagd op 26 oktober 2026. Vliegen gebouwd, nog te testen.*
4. **Eén sensorkastje** met de huidige sensor: eerst op tafel, dan in het veld. *Software gebouwd in [`sensor/`](../sensor/README.md), nog te testen met een bordje.*
5. **Centraal systeem, stap voor stap:**
   1. ontvangen en opslaan; *gebouwd, in de cloud*
   2. tonen op de veldkaart; *gebouwd*
   3. weer koppelen; *gebouwd (Open-Meteo)*
   4. regels voor wateradvies; *gebouwd (eenvoudige regels, versie 0)*
   5. foto-analyse op de laptop; *niveau 1 gebouwd (zonder getrainde AI); het leer-systeem voor de AI gebouwd op 9 november 2026, de AI zelf leert van foto's van je eigen veld*
   6. een server met accounts, zodat anderen kunnen meekijken; *gebouwd (Supabase)*
6. **Betere sensoren** (capacitief of landbouwsensoren), verspreid over de zones.

Bronnen:

- [Productpagina sensor (Bits & Parts)](https://www.bitsandparts.nl/bodemvochtigheidsmeter-analoog-digitaal-p109699)
- [KNMI Data Platform](https://www.knmi.nl/research/observations-data-technology/projects/knmi-data-platform)
- [Google Weather API, gebruik en kosten](https://developers.google.cn/maps/documentation/weather/usage-and-billing?authuser=5)
- [Open-Meteo-voorwaarden](https://open-meteo.com/en/terms)
- [Mavic Mini-specificaties](https://www.dji.com/support/product/mavic-mini)
