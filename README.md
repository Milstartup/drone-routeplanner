# Drone-routeplanner (prototype)

Een browser-app om fotovluchten te plannen voor een **DJI Mavic Mini** (het originele model uit 2019) boven een gewasveld, zoals broccoli. Je tekent een route of een veldgrens op een luchtfoto. De app maakt er vliegbanen van, laat zien waar de foto's vallen, schat lengte, vliegtijd en aantal foto's, en slaat alles op als JSON met GPS-coördinaten.

**Wat deze app niet doet**

- Hij is niet verbonden met een drone en verstuurt **geen vliegcommando's**. De simulatie is alleen een animatie in de browser.
- Het JSON-bestand is een **planningsbestand, geen DJI-missie**. De DJI Fly-app en de drone kunnen het niet uitvoeren.
- Er zit geen beeldanalyse (AI) in. De foto's worden na de vlucht door een ander systeem geanalyseerd.

## Starten op Windows

### Eenmalig

1. **Node.js installeren** (versie 22 of nieuwer; getest met 24.22.1 LTS). Op deze laptop is dat al gedaan met:
   ```bash
   winget install OpenJS.NodeJS.LTS
   ```
   Of download de LTS-versie van <https://nodejs.org>. Open daarna een **nieuw** terminalvenster, anders kent het venster `node` nog niet.
2. Ga naar de projectmap:
   ```bash
   cd C:\drone-routeplanner
   ```
3. Installeer de onderdelen. Dit duurt ongeveer een minuut en maakt de map `node_modules`:
   ```bash
   npm.cmd install
   ```

### Elke keer dat je de app wilt gebruiken

4. Start de app:
   ```bash
   npm.cmd run dev
   ```
5. Open <http://localhost:5173> in Edge of Chrome.
6. Stoppen: klik in het terminalvenster en druk op **Ctrl+C**.

> **Waarom `npm.cmd` en niet `npm`?** In PowerShell kan `npm` de foutmelding geven dat "het uitvoeren van scripts is uitgeschakeld". `npm.cmd` werkt altijd, zowel in PowerShell als in de Opdrachtprompt.

### Andere commando's

| Commando | Wat het doet |
|---|---|
| `npm.cmd test` | Draait de 68 automatische tests (rekenkern, validatie, JSON, bewerken). |
| `npm.cmd run typecheck` | Controleert de TypeScript-typen. |
| `npm.cmd run build` | Maakt een productieversie in `dist/`. |
| `npm.cmd run preview` | Toont die productieversie op <http://localhost:4173>. |

## Zo gebruik je het

1. **Zoek je veld op.** Typ bij *Kaart* een plaats of adres (bijvoorbeeld `Dronten`) of een coördinaat (`52.4985, 5.5402`) en klik op *Zoek*. Zoom in met het muiswiel.
2. **Teken de veldgrens.** Kies *Veld + vliegbanen*, klik op *Veldgrens tekenen* en klik de hoeken van het veld rondom aan. Druk op **Esc** als je klaar bent. De gele lijnen zijn de vliegbanen, de oranje stippellijnen de overgangen zonder foto's en de witte stipjes de fotoposities.
3. **Plaats het startpunt.** Klik op *Startpunt plaatsen* en daarna op de plek waar de drone opstijgt en landt (H).
4. **Stel de vlucht in:** hoogte, snelheid, foto-interval, baanafstand, randmarge en baanrichting. Daaronder zie je hoe groot één foto op de grond is en hoeveel de foto's overlappen.
5. **Bekijk de controle.** *Fout* (rood) blokkeert de simulatie en het opslaan als JSON. *Let op* (geel) is een waarschuwing.
6. **Bekijk de schatting** en klap *Aannames achter deze schatting* open om te zien waarop die rust. Die aannames kun je daar ook aanpassen.
7. **Simuleer.** Klik op *Start simulatie* en kies het tempo. De drone vliegt de route, de gemaakte foto's kleuren roze en het blauwe vlak is wat de camera op dat moment ziet. Met de schuifbalk spoel je door. Klik op *Stop* om weer te bewerken.
8. **Sla op.** *Download JSON* zet een `.routeplan.json` in je map Downloads. *JSON laden* opent zo'n bestand weer. *Opslaan* bewaart een kopie in deze browser. Je huidige plan wordt ook automatisch in de browser bewaard.

**Punten bewerken**

- Een punt verplaatsen: sleep het.
- Een punt tussenvoegen: klik op een **+** halverwege een lijn.
- Een punt verwijderen: klik in de lijst op **×**, of selecteer het en druk op **Delete**.
- Ongedaan maken en opnieuw: **Ctrl+Z** en **Ctrl+Y**.

**Eigen route.** In de stand *Eigen route* klik je zelf de routepunten in vliegvolgorde aan. Per stuk zet je met het vinkje *foto's* aan of uit. Met *Omkeren* draai je de vliegrichting om. Met *Omzetten naar eigen route* maak je van gegenereerde vliegbanen losse punten die je één voor één kunt aanpassen.

## Kaartdiensten en API-sleutels

| Kaartbeeld | Sleutel nodig? | Dekking | Voorwaarden |
|---|---|---|---|
| **Luchtfoto Nederland 8 cm / 25 cm (PDOK)**, standaard | Nee | Alleen Nederland | Open data van Beeldmateriaal Nederland, gratis via PDOK, licentie **CC BY 4.0**. De verplichte bronvermelding staat rechtsonder op de kaart. |
| **Satelliet wereldwijd (Esri World Imagery)** | Ja, ArcGIS Location Platform | Wereldwijd | Esri meldt een gratis tegoed van 2 miljoen basemap-tegels per maand en staat commerciële apps toe. Controleer de actuele prijzen en voorwaarden. "Powered by Esri" moet zichtbaar blijven. |
| **Stratenkaart (OpenStreetMap)** | Nee | Wereldwijd | Geen luchtfoto. Alleen voor licht gebruik; massaal of offline downloaden is niet toegestaan volgens het tegelbeleid van OpenStreetMap. |

- **Voor velden in Nederland heb je geen sleutel nodig.** De PDOK-luchtfoto's zijn bovendien scherper dan de meeste satellietbeelden.
- **Esri buiten Nederland aanzetten:**
  1. Maak een gratis account op <https://location.arcgis.com>.
  2. Maak een API-sleutel met toegang tot *Basemaps* en beperk die tot `http://localhost:5173`.
  3. Kopieer `.env.example` naar `.env.local` en vul de sleutel in achter `VITE_ARCGIS_API_KEY=`.
  4. Stop de app met Ctrl+C en start hem opnieuw met `npm.cmd run dev`.

  `.env.local` staat in `.gitignore` en komt dus niet in git. De sleutel is wel zichtbaar in de browser, dus gebruik deze opzet alleen lokaal.
- **Niet ingebouwd:**
  - Google-kaarttegels. De losse tegeladressen die je online ziet, mag je niet zomaar gebruiken; Google kan alleen via de eigen API's, met een eigen sleutel en voorwaarden.
  - Het gratis plan van MapTiler. Dat is alleen voor niet-commercieel gebruik.

Bronnen:

- PDOK-luchtfoto: <https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0?request=GetCapabilities&service=WMTS>
- Licentie per jaargang: <https://data.overheid.nl> (zoek op "luchtfoto beeldmateriaal")
- Esri: <https://developers.arcgis.com/esri-leaflet/maps/raster-tile-basemaps/display-multiple-basemap-layers/> en <https://location.arcgis.com/pricing/>
- OpenStreetMap-tegelbeleid: <https://operations.osmfoundation.org/policies/tiles/>

De zoekfunctie gebruikt de **PDOK Locatieserver** (gratis, geen sleutel, alleen Nederland). Coördinaten werken overal.

## Aannames achter de schatting

De schatting is een planning, geen belofte. De app gaat uit van het volgende:

- **Snelheid en wind:** constante snelheid langs de route en geen wind. Wind en kou maken een echte vlucht langer en de accu sneller leeg.
- **Routepunten:** per routepunt een vaste pauze voor afremmen, draaien en optrekken (standaard 3 s).
- **Opstijgen en landen:** recht omhoog bij het startpunt (2 m/s), recht naar het eerste punt, na het laatste punt terug naar het startpunt en recht omlaag landen (1,5 m/s).
- **Hoogte:** gemeten ten opzichte van het startpunt; het veld wordt als vlak aangenomen.
- **Foto's:**
  - Ze worden gepland op vaste afstand (snelheid × interval) langs de stukken met foto's.
  - Elke vliegbaan begint met een foto.
  - In bochten en overgangen worden geen foto's gemaakt.
- **Camera:**
  - De camera kijkt recht naar beneden, met de lange kant van de foto dwars op de vliegrichting.
  - Mavic Mini: 1/2.3"-sensor, 12 MP, diagonale beeldhoek 83°, foto 4000 × 3000. Op 30 m dekt één foto zo'n 42 × 32 m (ongeveer 1,1 cm per pixel).
- **Accu:**
  - DJI noemt maximaal 30 minuten vliegtijd (windstil, 14 km/u).
  - De planner rekent standaard met **20 minuten bruikbare tijd**, als reserve voor wind, kou en de terugweg.
- **Zicht (VLOS):** het verste routepunt mag standaard maximaal 500 m van het startpunt liggen. Dat is een aanname voor zichtafstand, geen wettelijke grens.
- **Berekening:** afstanden worden over het aardoppervlak berekend (haversine). Veldvormen worden in een platte projectie in meters berekend; die is nauwkeurig voor velden tot enkele kilometers.

Gebruikte specificaties van de Mavic Mini (bron: <https://www.dji.com/support/product/mavic-mini>):

- Topsnelheid 13 / 8 / 4 m/s in S / P / C-stand.
- Stijgen 2 m/s en dalen 1,8 m/s in de P-stand.
- Windbestendigheid 8 m/s.
- Fotostanden: losse foto en interval 2/3/5/7/10/15/20/30/60 s.

Volgens DJI bestuurt een app de Mavic Mini alleen in de **P-stand**. Daarom is de maximale snelheid in de planner **8 m/s**.

## Wat de controle bekijkt

| Onderdeel | Fout (blokkeert) | Let op |
|---|---|---|
| Veldgrens | Minder dan 3 punten, punten op dezelfde plek, grens kruist zichzelf, kleiner dan 100 m², breder dan 5 km, geen enkele vliegbaan past | Groter dan 50 ha, overgangen tussen banen lopen buiten de grens (onregelmatige velden) |
| Eigen route | Minder dan 2 punten | Dubbele punten, punten buiten de veldgrens, nergens foto's |
| Hoogte | Geen getal, onder 5 m, boven 120 m (EU open categorie) | Onder 15 m (obstakels) |
| Snelheid | Geen getal, 0 of minder, boven 8 m/s (P-stand) | Boven 6 m/s (weinig marge bij wind, onscherpte) |
| Baanafstand, randmarge, richting | Geen getal, baanafstand onder 2 m, negatieve marge | Baanafstand groter dan de fotobreedte (stroken zonder foto) |
| Foto-interval | Geen getal, onder 0,5 s | Onder 2 s (kortste intervalstand van de Mavic Mini), foto's sluiten niet op elkaar aan |
| Startpunt en accu | (geen) | Geen startpunt, verste punt verder dan de zichtafstand, vliegtijd langer dan de bruikbare accutijd |
| Geladen bestanden | Geen JSON, verkeerd formaat, ongeldige GPS-coördinaten of instellingen | (geen) |

## Het JSON-bestand

Zie [docs/ROUTEBESTAND.md](docs/ROUTEBESTAND.md). Kort samengevat:

- Coördinaten in WGS84 (decimale graden) en hoogte in meters boven het startpunt.
- Het bestand bevat de invoer (grens, routepunten, startpunt, instellingen, aannames) en de berekende route met fotoposities.
- Bovenin staat expliciet dat het geen DJI-missiebestand is.

## Opbouw van de code

```
src/
  core/      Rekenkern in gewone TypeScript, zonder React, zonder kaart en zonder drone:
             geometrie, vliegbaangenerator, fotoposities, tijdlijn, schatting,
             validatie, JSON-formaat. Hier staan ook alle tests.
  map/       Kaartbronnen (URL, bronvermelding, voorwaarden).
  ui/        React-schermen: kaart (Leaflet), panelen, simulatieklok, opslag in de browser.
docs/        Routebestand, architectuur, stappenplan en onderzoek naar de DJI Mobile SDK.
  voorbeelden/  Voorbeeldbestanden in alle dataformaten.
ios/         De iPhone-app Veldvlucht (Swift, Xcode op een Mac). Zie ios/README.md.
```

- De **routeplanner staat los van de dronebesturing.** `src/core` importeert alleen andere bestanden uit `src/core`.
- Een test (`separation.test.ts`) bewaakt dat: hij faalt zodra er React, Leaflet of DJI-code in de kern terechtkomt.
- Een latere iPhone-app hoeft alleen het JSON-bestand te lezen.

**Gebruikte techniek:**

- React 19 en TypeScript 7.
- Vite 8 (ontwikkelserver en build).
- Leaflet 1.9 met react-leaflet 5 (kaart).
- Vitest 5 (tests).

Leaflet is gekozen omdat het licht is, gewone kaarttegels toont en zelf geen sleutel nodig heeft.

## De iPhone-app

De iPhone-app **Veldvlucht** staat in [`ios/`](ios/README.md). Hij is gebouwd, maar nog niet getest met de drone:

- **Drone:** de haalbaarheidstest (aanmelden bij DJI, verbinden, accu, GPS, firmware en één foto op de grond);
- **Route:** een `.routeplan.json` van deze planner inlezen, opnieuw controleren en op de kaart tonen;
- **Veldkaart:** het veld met wateradvies, markeringen, sensoren en weer, nu nog met voorbeeldgegevens.

Vliegen kan de app nog niet. Zie verder:

- [docs/STAPPENPLAN.md](docs/STAPPENPLAN.md) voor de volgende stappen;
- [docs/ARCHITECTUUR.md](docs/ARCHITECTUUR.md) voor het hele systeem (drone, bodemvochtsensoren, weer, centraal systeem met AI en de veldkaart in de app);
- [docs/DJI-MOBILE-SDK-V4.md](docs/DJI-MOBILE-SDK-V4.md) voor het onderzoek en het ontwerp van de drone-app.

In het kort:

- Een iPhone-app bouwen kan alleen op een **Mac met Xcode**. Op een Intel-Mac gaat het met een oudere Xcode-versie (zie het stappenplan).
- De Mavic Mini kan geen routes zelfstandig uitvoeren. De iPhone moet de drone continu besturen.
- De DJI-SDK voor iOS wordt sinds 2022 niet meer bijgewerkt en heeft problemen met de huidige Xcode-versies.
