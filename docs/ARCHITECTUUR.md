# Architectuur: drone, sensoren, weer en centraal systeem

Vastgelegd op 25 oktober 2026. Dit is een **ontwerp**. Alleen de routeplanner bestaat al. De dataformaten hieronder zijn een eerste voorstel (versie 0) en nog nergens gebouwd.

## Doel

Eén systeem dat per broccoliveld drie bronnen samenbrengt:

- de foto's van de drone;
- de metingen van bodemvochtsensoren in het veld;
- de weersverwachting.

Een AI in het centrale systeem bepaalt daaruit **hoeveel water welke delen van het veld nodig hebben**, en **markeert planten of plekken die aandacht nodig hebben**. Alles is overzichtelijk te zien op een **veldkaart in de iPhone-app**.

## Overzicht

```
 VELD                                  CENTRAAL SYSTEEM (nog te bouwen)           IPHONE-APP
 ────                                  ────────────────────────────────           ──────────
 Sensorkastjes ──LoRaWAN/mobiel──►  ┐
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
| Drone-app (vliegen + foto's) | Ontwerp | [DJI-MOBILE-SDK-V4.md](DJI-MOBILE-SDK-V4.md), [STAPPENPLAN.md](STAPPENPLAN.md) |
| Sensorkastje | Ontwerp | Dit document, hoofdstuk 2 |
| Centraal systeem + AI | Ontwerp | Dit document, hoofdstuk 4 |
| Veldkaart in de iPhone-app | Ontwerp | Dit document, hoofdstuk 5 |

## Scheidingsregels

Elk onderdeel heeft één taak en praat met de andere alleen via vastgelegde dataformaten (hoofdstuk 6):

- **De routeplanner** plant alleen. `src/core` bevat geen UI-, drone-, sensor- of AI-code; `separation.test.ts` bewaakt dat.
- **Het vluchtdeel van de iPhone-app** doet alleen vliegen en foto's maken. Tijdens een vlucht staan er geen sensor- of AI-schermen in de weg.
- **De sensorkastjes** meten en versturen alleen. Ze nemen geen beslissingen.
- **Het centrale systeem** is de enige plek waar gegevens worden gecombineerd en waar de AI draait.
- **De veldkaart** toont alleen wat het centrale systeem klaarzet. De app rekent zelf geen advies uit.

## 1. Drone en foto's

- Het vliegen en het fotograferen werken zoals beschreven in [STAPPENPLAN.md](STAPPENPLAN.md): de app maakt een losse foto op elke geplande fotopositie.
- Na de vlucht gaan de foto's (van de microSD-kaart) plus het **fotolog** van de app naar het centrale systeem.
- **Wat de camera kan:** de Mavic Mini heeft een gewone kleurencamera (RGB, 12 MP). Op 30 m is dat ongeveer 1,1 cm per pixel, dus losse broccoliplanten zijn goed te zien.
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

**Versturen.** Op een akker is meestal geen wifi. De opties:

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

**Uitgangspunten:**

- **Advies, geen opdracht.** De AI geeft advies. De teler beslist en controleert; de app laat bij elk advies zien waarop het gebaseerd is.
- **Bewaar ruwe gegevens altijd**, zodat je later met betere regels of modellen opnieuw kunt rekenen.
- **Waar en hoe het draait**, bijvoorbeeld een clouddienst, een database met kaartfuncties en een eigen API voor de app: dat is nog een open keuze.

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

### Sensormeting

```json
{
  "format": "veld/sensormeting",
  "version": 0,
  "sensorId": "veld-noord-s1",
  "fieldId": "veld-noord",
  "location": { "lat": 52.4991, "lng": 5.5431 },
  "depthCm": 15,
  "time": "2026-10-25T06:00:00+02:00",
  "raw": 612,
  "moisturePercent": null,
  "calibration": null,
  "batteryVolt": 3.9
}
```

- `raw` is de ruwe sensorwaarde.
- `moisturePercent` en `calibration` blijven leeg tot de sensor geijkt is.

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
      "time": "2026-10-25T10:14:03+02:00",
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
  "properties": { "format": "veld/resultaten", "version": 0, "fieldId": "veld-noord", "createdAt": "2026-10-25T12:00:00+02:00" },
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

## 7. Open vragen

1. **Hoe groot is het veld**, en hoeveel sensoren wil of kun je plaatsen?
2. **Is er LoRaWAN-dekking of mobiel bereik** op het veld?
3. **Is het gebruik commercieel?** Dat bepaalt welke weerdienst en welke kaartdiensten mogen.
4. **Hoe wordt er water gegeven:** met de hand, met een haspel of druppelslangen? Dat bepaalt hoe fijn het advies moet zijn (per zone, per strook).
5. **Hoe vaak wordt er gevlogen**, en hoe snel moet het advies er daarna zijn?
6. **Waar gaat het centrale systeem draaien** (cloud of eigen computer), en wie mag de gegevens zien?

## 8. Bouwvolgorde

Deze volgorde staat ook in [STAPPENPLAN.md](STAPPENPLAN.md).

1. **Dataformaten** van hoofdstuk 6 vastleggen, met voorbeeldbestanden.
2. **Veldkaart in de iPhone-app** met voorbeeldgegevens.
3. **Drone-app:** de haalbaarheidstest, daarna vliegen en foto's.
4. **Eén sensorkastje** met de huidige sensor: eerst op tafel, dan in het veld.
5. **Centraal systeem, stap voor stap:**
   1. ontvangen en opslaan;
   2. tonen op de veldkaart;
   3. weer koppelen;
   4. regels voor wateradvies;
   5. AI voor wateradvies en markeringen.
6. **Betere sensoren** (capacitief of landbouwsensoren), verspreid over de zones.

Bronnen:

- [Productpagina sensor (Bits & Parts)](https://www.bitsandparts.nl/bodemvochtigheidsmeter-analoog-digitaal-p109699)
- [KNMI Data Platform](https://www.knmi.nl/research/observations-data-technology/projects/knmi-data-platform)
- [Google Weather API, gebruik en kosten](https://developers.google.cn/maps/documentation/weather/usage-and-billing?authuser=5)
- [Open-Meteo-voorwaarden](https://open-meteo.com/en/terms)
- [Mavic Mini-specificaties](https://www.dji.com/support/product/mavic-mini)
