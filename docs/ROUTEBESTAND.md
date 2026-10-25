# Het routebestand (`.routeplan.json`)

De planner slaat een plan op als JSON. Dit bestand is het **contract tussen de planner en een latere drone-app**.

> **Dit is geen DJI-missiebestand.** Geen enkele DJI-app of DJI-drone kan het rechtstreeks uitvoeren. Een drone-app moet het zelf inlezen, opnieuw controleren en omzetten naar eigen besturing. Datzelfde staat ook in het veld `notice` van elk bestand.

## Afspraken

- **Coördinaten:** WGS84 (EPSG:4326) in decimale graden, afgerond op 7 decimalen (ongeveer 1 cm).
- **Hoogte:** meters boven het startpunt (relatief). Er staat geen hoogte boven zeeniveau in het bestand.
- **Snelheid** in m/s, **tijd** in seconden, **afstand** in meters.
- **Twee soorten velden:**
  - Bij het laden gebruikt de planner alleen de **invoer**: `mode`, `settings`, `assumptions`, `home`, `boundary` en `routePoints`.
  - Het blok `derived` is ter informatie. De planner rekent het bij het laden opnieuw uit uit de invoer.
- **Versies:** het bestand heeft `format` en `version`. Bestanden met een ander formaat of een andere versie worden geweigerd, met een duidelijke melding.

## Velden

| Veld | Type | Betekenis |
|---|---|---|
| `format` | tekst | Altijd `"drone-routeplanner/plan"` |
| `version` | getal | Altijd `1` |
| `notice` | tekst | Waarschuwing dat dit geen DJI-missie is |
| `createdAt` | tekst | Tijdstip van opslaan (ISO 8601, UTC) |
| `coordinateSystem`, `altitudeReference` | tekst | De afspraken hierboven, voor menselijke lezers |
| `name` | tekst | Naam van de route |
| `mode` | `"field"` of `"route"` | Veld met gegenereerde vliegbanen, of een eigen route |
| `settings.altitudeM` | getal | Vlieghoogte boven het startpunt |
| `settings.speedMps` | getal | Snelheid |
| `settings.lineSpacingM` | getal | Afstand tussen vliegbanen (alleen bij veld) |
| `settings.photoIntervalS` | getal | Seconden tussen foto's |
| `settings.lineAngleDeg` | getal of `null` | Kompasrichting van de banen; `null` = automatisch, langs de langste zijde |
| `settings.edgeMarginM` | getal | Minimale afstand tussen banen en grens |
| `assumptions.*` | getallen | Stijg- en daalsnelheid, pauze per routepunt, bruikbare vliegtijd (s), maximale afstand tot het startpunt (m) |
| `home` | `{lat, lng}` of `null` | Start- en landingsplek |
| `boundary` | lijst `{lat, lng}` | Hoekpunten van de veldgrens, zonder het eerste punt te herhalen |
| `routePoints` | lijst `{lat, lng, capture}` | Eigen routepunten; `capture` = foto's maken op het stuk naar het volgende punt |
| `derived.waypoints` | lijst `{index, lat, lng, altitudeM}` | De punten die gevlogen worden, in volgorde |
| `derived.legs` | lijst `{from, to, capture}` | De stukken tussen twee punten (index in `waypoints`) en of er foto's op vallen |
| `derived.photoPoints` | lijst `{index, lat, lng, legIndex}` | Geplande fotoposities en het stuk waar ze op liggen |
| `derived.estimate` | object | Totale afstand, vliegtijd, aantal foto's, fotoafstand, veldoppervlak |

## Voorbeeld

Een ingekorte eigen route met drie punten, zonder startpunt. Op het eerste stuk worden foto's gemaakt, op het tweede niet.

```json
{
  "format": "drone-routeplanner/plan",
  "version": 1,
  "notice": "Planningsbestand van de drone-routeplanner (prototype). Dit is GEEN DJI-missiebestand en kan niet rechtstreeks door een DJI-drone of DJI-app worden uitgevoerd. Een toekomstige drone-app moet de route zelf inlezen, opnieuw controleren en omzetten naar eigen commando's.",
  "createdAt": "2026-10-25T12:00:00.000Z",
  "coordinateSystem": "WGS84 (EPSG:4326), decimale graden",
  "altitudeReference": "meter boven het startpunt",
  "name": "Proefstrook",
  "mode": "route",
  "settings": {
    "altitudeM": 30,
    "speedMps": 4,
    "lineSpacingM": 20,
    "photoIntervalS": 3,
    "lineAngleDeg": null,
    "edgeMarginM": 5
  },
  "assumptions": {
    "ascentSpeedMps": 2,
    "descentSpeedMps": 1.5,
    "waypointPauseS": 3,
    "usableFlightTimeS": 1200,
    "maxDistanceFromHomeM": 500
  },
  "home": null,
  "boundary": [],
  "routePoints": [
    { "lat": 52.5, "lng": 5.5, "capture": true },
    { "lat": 52.5, "lng": 5.5007, "capture": false },
    { "lat": 52.5004, "lng": 5.5007, "capture": true }
  ],
  "derived": {
    "waypoints": [
      { "index": 0, "lat": 52.5, "lng": 5.5, "altitudeM": 30 },
      { "index": 1, "lat": 52.5, "lng": 5.5007, "altitudeM": 30 },
      { "index": 2, "lat": 52.5004, "lng": 5.5007, "altitudeM": 30 }
    ],
    "legs": [
      { "from": 0, "to": 1, "capture": true },
      { "from": 1, "to": 2, "capture": false }
    ],
    "photoPoints": [
      { "index": 0, "lat": 52.5, "lng": 5.5, "legIndex": 0 },
      { "index": 1, "lat": 52.5, "lng": 5.5001773, "legIndex": 0 },
      { "index": 2, "lat": 52.5, "lng": 5.5003546, "legIndex": 0 },
      { "index": 3, "lat": 52.5, "lng": 5.5005318, "legIndex": 0 }
    ],
    "estimate": {
      "totalDistanceM": 91.86,
      "flightTimeS": 25.97,
      "photoCount": 4,
      "photoSpacingM": 12,
      "fieldAreaM2": null
    }
  }
}
```

## Regels voor een drone-app die dit bestand leest

1. **Weiger alles wat je niet kent.** Controleer `format`, `version` en alle coördinaten (lat −90..90, lng −180..180).
2. **Controleer opnieuw.** Gebruik dezelfde regels als de planner, plus wat alleen de app weet: actuele accu, GPS-ontvangst, wind, no-fly-zones en de werkelijke plek van het startpunt.
3. **Het plan is een wens, geen opdracht.** De piloot bevestigt de route en houdt altijd de mogelijkheid om over te nemen (zie [DJI-MOBILE-SDK-V4.md](DJI-MOBILE-SDK-V4.md)).
4. **Hoogte is relatief.** Zet de drone op dezelfde plek en hoogte op als `home`, of reken het verschil door.
