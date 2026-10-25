# Stappenplan: van routeplanner naar drone, sensoren en veldkaart

Stand op 25 oktober 2026:

- **Klaar:** de routeplanner (browser-app in deze repository).
- **Nog te bouwen:**
  - de iPhone-app die de route vliegt en onderweg foto's maakt met de camera van de drone (stap 0 t/m 6);
  - daarnaast de bodemvochtsensoren, het centrale systeem met de AI en de veldkaart in de iPhone-app (stap 7 t/m 9).

Achtergrond:

- [ARCHITECTUUR.md](ARCHITECTUUR.md): hoe drone, sensoren, weer en centraal systeem samenkomen, met de dataformaten.
- [DJI-MOBILE-SDK-V4.md](DJI-MOBILE-SDK-V4.md): onderzoek en ontwerp van de drone-app.
- [ROUTEBESTAND.md](ROUTEBESTAND.md): het bestand dat de planner aan de app geeft.

## Hoe de foto's onderweg werken

- **De planner** berekent de fotoposities: een foto elke *snelheid × foto-interval* meter langs de stukken met foto's. Elke vliegbaan begint met een foto. Ze staan met GPS-coördinaten in `derived.photoPoints` van het routebestand.
- **De iPhone-app** laat de drone de route vliegen zonder te stoppen. Komt de drone binnen een paar meter van de volgende fotopositie, dan geeft de app de camera van de drone het commando voor één foto (`DJICameraShootPhotoModeSingle` en `startShootPhotoWithCompletion:`).
- **De camera** slaat de foto op de **microSD-kaart in de drone** op: JPEG, 12 MP, 4000 × 3000.
- **De app** telt via `camera:didGenerateNewMediaFile:` welke foto's echt gelukt zijn. Zo kan een onderbroken vlucht later precies daar verder.
- **Harde grens:** minimaal **2 seconden** tussen twee foto's (kortste intervalstand van de Mavic Mini). Bij 4 m/s is dat minimaal 8 m tussen foto's. De planner waarschuwt al bij kortere intervallen.
- **Na de vlucht** gaan de foto's van de microSD-kaart naar het centrale systeem.
  - Controleer bij de eerste test of de Mavic Mini GPS-gegevens in de foto's (EXIF) zet.
  - De app bewaart daarnaast een logbestand met per foto het nummer, de tijd en de positie.

## Stap 0: Mac en hardware klaarmaken (zelf doen)

1. **Apple-chip:** Apple-menu → *Over deze Mac*. Daar moet **Chip: Apple M…** staan; de huidige Xcode draait alleen op Apple-chips. Controleer ook of macOS up-to-date is (Xcode 27 vraagt macOS Tahoe 26.6 of nieuwer).
2. **Xcode** installeren uit de Mac App Store. Open het één keer en log in met je Apple ID (Xcode → Settings → Accounts).
3. **DJI-ontwikkelaarsaccount** maken op <https://developer.dji.com>. De App Key volgt in stap 2, als de app een Bundle ID heeft.
4. **Hardware testen met DJI Fly:**
   - Maakt je iPhone verbinding met de afstandsbediening van de Mavic Mini?
   - Zie je het camerabeeld?
   - Noteer het iPhone-model. Bij USB-C-iPhones (15 en nieuwer) zijn problemen gemeld.
   - Noteer de firmwareversie van de drone. De iOS-SDK noemt 01.00.0500; of nieuwere firmware werkt, is niet bevestigd.
5. **Node.js** op de Mac, als je de planner ook daar wilt draaien: de LTS-versie van <https://nodejs.org>.

## Stap 1: project op de Mac

Het project staat als **privé-repository** op <https://github.com/Milstartup/drone-routeplanner>. Omdat de repository privé is, moet je op de Mac inloggen bij GitHub. Twee manieren:

- **Makkelijkst: GitHub Desktop**
  1. Download het programma van <https://desktop.github.com> en log in met je GitHub-account.
  2. Kies *File → Clone Repository → Milstartup/drone-routeplanner*.
  3. Kies een map, bijvoorbeeld `~/Projects`.
- **Met de Terminal:** log eerst in met de GitHub CLI (`gh auth login`), en haal het project dan op:
  ```bash
  gh repo clone Milstartup/drone-routeplanner
  ```

Ga daarna in de Terminal naar de projectmap:

```bash
cd drone-routeplanner
```

De planner draaien op de Mac (op de Mac werkt gewoon `npm`):

```bash
npm install
```
```bash
npm run dev
```

Start daarna een **nieuwe Claude-sessie in deze map op de Mac**. Die sessie leest eerst:

- dit bestand;
- `docs/ARCHITECTUUR.md`;
- `docs/DJI-MOBILE-SDK-V4.md`;
- `docs/ROUTEBESTAND.md`.

Zet de iPhone-app in een eigen map, bijvoorbeeld `ios/`. Neem niets van de dronecode op in `src/core`; dat bewaakt de test `separation.test.ts`.

## Stap 2: haalbaarheidstest (go/no-go)

Bouw een minimale iPhone-app die **alleen**:

1. zich aanmeldt bij DJI (`DJISDKAppKey` in Info.plist, `registerAppWithDelegate:`);
2. verbinding maakt met de drone (`startConnectionToProduct`, `productConnected:`);
3. accu, GPS-satellieten en de firmwareversie toont;
4. **op de grond één foto maakt** met de camera van de drone.

Vlieg hierbij nog niet.

- **Lukt dit:** de rest is gewoon werk.
- **Lukt het niet:** kijk naar de alternatieven in hoofdstuk 7 van het DJI-document. Mogelijke oorzaken:
  - bouwproblemen met de oude SDK en de huidige Xcode (zie GitHub-issue #560 van de DJI-SDK);
  - de iPhone-verbinding;
  - de App Key.

## Stap 3: route en foto's, zonder te vliegen

- Het `.routeplan.json` inlezen (AirDrop of de Bestanden-app), opnieuw valideren en op een kaart tonen.
- Een stuurlus van ongeveer 10 Hz met Virtual Stick en het fotomoment per fotopositie uitproberen in de **ingebouwde simulator van de DJI-SDK**. Haal de propellers eraf als de drone voor de simulator aangesloten is.
- Testen in de simulator:
  - Klopt de vliegrichting (pitch/roll)?
  - Worden de foto's op de goede plekken gemaakt?
  - Gaat hervatten na een pauze goed?

## Stap 4: veiligheid

Werk dit uit volgens hoofdstuk 6 van het DJI-document:

- **Knoppen:** Pauze, Overnemen en Naar huis, groot op het scherm.
- **Sticks bewaken:** komt de piloot aan de sticks, dan stopt de app direct met sturen.
- **Verbindingsverlies:** stel vooraf `setConnectionFailSafeBehavior` in op GoHome, met een veilige terugkeerhoogte.
- **Lage accu:**
  - De app breekt de route op tijd af en bewaart de voortgang.
  - De slimme terugkeer van de drone zelf heeft altijd voorrang.
- **Geen automatisch hervatten** na een overname of een verbroken verbinding.

## Stap 5: eerste echte vluchten

1. Een klein, open stuk veld, een korte route (2–3 banen), goed weer en weinig wind. Houd de drone altijd zelf in het oog.
2. Controleer daarna:
   - Zijn alle geplande foto's gemaakt?
   - Liggen ze op de goede plek?
   - Zijn ze scherp genoeg om de planten te beoordelen?
   - Bevatten ze GPS-gegevens?
3. Daarna stap voor stap groter, tot een heel veld (verdeeld over meerdere accu's als de planner dat aangeeft).

## Stap 6: foto's naar het centrale systeem

- Foto's van de microSD-kaart kopiëren, samen met het fotolog van de app.
- Het fotolog volgt het formaat `veld/fotolog` uit hoofdstuk 6 van [ARCHITECTUUR.md](ARCHITECTUUR.md).
- Zolang het centrale systeem er nog niet is: bewaar foto's en fotolog per vlucht in een eigen map.

## Stap 7: veldkaart in de iPhone-app (met voorbeeldgegevens)

Dit kan al **voordat** het centrale systeem of de AI bestaat, en naast de stappen 2 t/m 5.

1. Maak voorbeeldbestanden in de formaten van [ARCHITECTUUR.md](ARCHITECTUUR.md):
   - resultaten (zones en markeringen);
   - sensormetingen.
2. Bouw het veldkaartscherm:
   - luchtfoto, veldgrens en zones gekleurd naar wateradvies;
   - markeringen voor planten die aandacht nodig hebben (tik voor de reden en de foto);
   - sensorpunten met de laatste meting;
   - een weerbalk.
3. Test het in het veld: is alles in één oogopslag duidelijk, ook in de zon?

## Stap 8: sensorkastje

1. Op tafel:
   - de huidige sensor op een ESP32- of LoRa-bordje aansluiten en de **analoge** uitgang uitlezen;
   - de voeding alleen aanzetten tijdens een meting, tegen slijtage.
2. Versturen in het formaat `veld/sensormeting`:
   - eerst via wifi op tafel;
   - daarna via LoRaWAN of het mobiele netwerk, als het veld daar dekking heeft.
3. IJken met droge en natte grond van het veld.
4. In het veld: waterdicht kastje, accu (eventueel met zonnepaneel) en een vaste, ingemeten GPS-positie.
5. Later: betere sensoren (capacitief of landbouwsensoren), minstens één per zone.

## Stap 9: centraal systeem en AI

Stap voor stap, zodat elke stap zelf al nut heeft:

1. **Ontvangen en opslaan** van sensormetingen, foto's met fotolog en de veldgrens.
2. **Tonen op de veldkaart** in de app: eerst alleen de ruwe gegevens.
3. **Weer koppelen** via een officiële weerdienst (KNMI, Google Weather API of een betaald Open-Meteo-abonnement; zie [ARCHITECTUUR.md](ARCHITECTUUR.md) hoofdstuk 3).
4. **Wateradvies met eenvoudige regels**, die de teler controleert.
5. **AI**, als er genoeg gegevens en gelabelde foto's zijn:
   - wateradvies per zone;
   - het markeren van planten die aandacht nodig hebben.

Beantwoord eerst de open vragen uit hoofdstuk 7 van [ARCHITECTUUR.md](ARCHITECTUUR.md) (veldgrootte, dekking, commercieel gebruik, manier van water geven).
