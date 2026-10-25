# Veldvlucht: de iPhone-app

De iPhone-app uit [STAPPENPLAN.md](../docs/STAPPENPLAN.md). Hij heeft drie tabbladen, elk los van de andere:

| Tabblad | Wat het doet | Stap |
|---|---|---|
| **Drone** | De haalbaarheidstest: aanmelden bij DJI, verbinden met de Mavic Mini, accu, GPS en firmware tonen, en **op de grond één foto maken**. | 2 |
| **Route** | Een routebestand van de planner inlezen, opnieuw controleren en op de luchtfoto tonen. | 3 (eerste deel) |
| **Veldkaart** | Het veld met stroken in blauw, geel of rood, markeringen, sensoren en het weer. Nu nog met **voorbeeldgegevens**. | 7 |

**Wat de app niet doet:** hij stuurt **geen vliegcommando's** en toont geen live camerabeeld. De fotoknop werkt alleen als de drone niet vliegt. Vliegen komt pas na een geslaagde test met de drone.

## Wat er in deze map staat

| Bestand of map | Wat het is | In git? |
|---|---|---|
| `Veldvlucht.xcworkspace` | **Dit open je in Xcode.** Bundelt de app en de DJI-SDK. | Ja |
| `Veldvlucht.xcodeproj` | Het Xcode-project van de app. Niet los openen, maar via de workspace. | Ja |
| `Veldvlucht/` | De schermen en de DJI-koppeling (Swift), plus `Info.plist`. | Ja |
| `VeldvluchtKern/` | Het rekenwerk zonder drone of scherm: routebestand, controles, dataformaten. Met tests. | Ja |
| `../docs/voorbeelden/` | Voorbeeldbestanden in alle dataformaten. Gaan mee in de app als map `voorbeelden`. | Ja |
| `Config/Veldvlucht.xcconfig` | Instellingen; leest `Lokaal.xcconfig` in. | Ja |
| `Config/Lokaal.voorbeeld.xcconfig` | Voorbeeld van wat er in `Lokaal.xcconfig` hoort, zonder echte sleutel. | Ja |
| `Config/Lokaal.xcconfig` | **Je DJI App Key** en je Apple-team. Alleen op deze Mac. | **Nee** (`.gitignore`) |
| `Podfile`, `Podfile.lock` | Welke DJI-SDK CocoaPods binnenhaalt: precies versie 4.16.2. | Ja |
| `Gemfile`, `Gemfile.lock`, `.bundle/config` | Welke CocoaPods-versie gebruikt wordt: precies 1.17.0. | Ja |
| `Pods/` | De gedownloade DJI-SDK (77 MB). Komt terug met `pod install`. | Nee |
| `vendor/` | CocoaPods zelf, alleen voor deze map geïnstalleerd. | Nee |

## Wat er al gedaan is (25 oktober 2026)

- **CocoaPods 1.17.0** geïnstalleerd, alleen in de map `ios/vendor/`. Er is niets aan macOS veranderd en er was geen beheerderswachtwoord nodig. CocoaPods bewaart wel een cache in je thuismap (`~/.cocoapods` en `~/Library/Caches/CocoaPods`).
  - **Gecontroleerd voor installatie:**
    - Het is het officiële pakket `cocoapods` op rubygems.org, beheerd door het CocoaPods-team, met 142 miljoen downloads.
    - Versie 1.17.0 is op 6 juli 2026 uitgebracht door een van de vaste beheerders. Dezelfde versie staat op GitHub (<https://github.com/CocoaPods/CocoaPods/releases>).
    - De licentie is MIT.
    - Er zijn geen veiligheidsmeldingen over deze versie gevonden. De bekende lekken uit 2024 zaten in de server van CocoaPods, niet in dit programma, en zijn al in 2023 gedicht.
  - **Waar de DJI-SDK vandaan komt:** het CocoaPods-recept voor `DJI-SDK-iOS` 4.16.2 is gelijk aan dat in DJI's eigen GitHub-repository. Het downloadt de SDK van DJI's eigen server (`djicdn.com`).
- `pod install` heeft de **DJI Mobile SDK 4.16.2** binnengehaald.
- De app is **gebouwd zonder fouten of waarschuwingen** met Xcode 16.4.
  - Dat was een proefbouw zonder ondertekening en met een nep-sleutel.
  - Gecontroleerd: de DJI-terugmeldingen hebben de goede namen, en de App Key komt in de app terecht.
- `Config/Lokaal.xcconfig` is aangemaakt met je Apple-team (Personal Team). **Alleen de App Key moet je er zelf nog in zetten.**
- **Nog niet getest:** de app op je iPhone met de drone. Dat is de test hieronder.
  - De iPhone-simulator kon vanuit Claude's sessie niet opstarten. Voor deze test maakt dat niet uit: de drone werkt alleen met een echte iPhone.

**Erbij gekomen op 26 oktober 2026:**

- Het tabblad **Route** (zie "Een route inlezen" hieronder).
- Het tabblad **Veldkaart** (zie "De veldkaart" hieronder).
- Het rekenpakket `VeldvluchtKern` met **31 tests die allemaal slagen**.
- De app bouwt nog steeds zonder fouten of waarschuwingen.
- **Niet getest:** hoe de schermen er op de iPhone uitzien. De simulator werkte niet, dus dat zie je pas als je de app op je iPhone zet. Laat het Claude weten als iets er vreemd uitziet.

## Eenmalig: je App Key invullen

Je hoeft de App Key **aan niemand te geven, ook niet aan Claude**. Je zet hem zelf in een bestand dat niet in git komt.

1. Open de Terminal en ga naar de projectmap:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner
   ```
2. Open het sleutelbestand in TextEdit:
   ```bash
   open -a TextEdit ios/Config/Lokaal.xcconfig
   ```
3. Zoek de regel `DJI_APP_KEY =` en plak je App Key **direct achter het =-teken**, zonder aanhalingstekens. Bijvoorbeeld: `DJI_APP_KEY = 0123abcd...`
4. Bewaar met **Cmd+S** en sluit TextEdit.
5. Controleer dat de sleutel niet in git komt:
   ```bash
   git status
   ```
   In de lijst mag `ios/Config/Lokaal.xcconfig` **niet** voorkomen.

Vergeet je dit, dan stopt Xcode het bouwen met de melding *"De DJI App Key ontbreekt"*.

## De app op je iPhone zetten

1. Verbind de iPhone met de kabel met de Mac.
2. Open de workspace (**niet** het `.xcodeproj`):
   ```bash
   open ios/Veldvlucht.xcworkspace
   ```
3. Kies bovenaan in Xcode het scheme **Veldvlucht** en daarnaast je **iPhone 13** als doel.
4. Het team voor het ondertekenen staat al ingevuld via `Lokaal.xcconfig`. Geeft het tabblad *Signing & Capabilities* toch een fout, kies dan bij *Team* je Personal Team.
5. Klik op ▶ (Run). De eerste keer duurt het bouwen een paar minuten.
6. Opent de app niet omdat de ontwikkelaar "niet vertrouwd" is, vertrouw dan je profiel op de iPhone: *Instellingen → Algemeen → VPN en apparaatbeheer*.

**Let op:** met een gratis Apple ID verloopt de app na ongeveer een week. Zet hem daarna opnieuw op de iPhone met ▶ in Xcode.

## De test op de grond

**Voorbereiding:**

- Accu's van de drone en de afstandsbediening opgeladen.
- **Propellers eraf.**
- Een **microSD-kaart in de drone**.
- **DJI Fly afgesloten:** veeg de app weg in het app-overzicht van de iPhone.
- De iPhone heeft **internet** (wifi of 4G): dat is nodig voor de eerste aanmelding bij DJI.
- Voor GPS: doe de test **buiten**, met vrij zicht op de lucht. Binnen ziet de drone weinig of geen satellieten.

**Zo doe je de test:**

1. **Open Veldvlucht** op de iPhone. Stap 1 op het scherm moet groen worden: **Aangemeld**.
   - Vraagt de app om je locatie of Bluetooth: kies *Sta toe bij gebruik van app*. De DJI-software gebruikt die voor de Fly Safe-regels.
2. **Zet de afstandsbediening aan** en sluit de iPhone met de kabel aan op de afstandsbediening.
   - Vraagt de iPhone om DJI Fly te openen, kies dan **Negeer**.
   - In stap 2 wordt *iPhone ↔ afstandsbediening* groen.
3. **Zet de drone aan.** Na een tijdje wordt *Afstandsbediening ↔ drone* groen en verschijnt het model.
4. **Bekijk stap 3:**
   - **Accu:** percentage en spanning.
   - **GPS-satellieten:** buiten na een paar minuten liefst 10 of meer.
   - **Firmware:** hoort **01.00.0500** te zijn (groen). Een andere versie staat in oranje.
5. **Bekijk stap 4.** Bij *SD-kaart* staat hoeveel foto's er nog op passen.
6. **Druk op "Maak één foto".** Gelukt als er staat: *Gelukt: DJI_xxxx.JPG*.
7. **Druk op "Kopieer logboek"** en plak de tekst in een bericht aan Claude, of in een notitie. Daarmee staat de uitslag vast.

**Na de test:** haal de microSD-kaart uit de drone en bekijk de foto op de Mac.

- Open hem in Voorvertoning en kies *Extra → Toon info*. Staat er een tabblad met GPS of een locatie, dan zet de Mavic Mini GPS in de foto's.
- Dat zal alleen zo zijn als de drone op het moment van de foto GPS had.

## Een route inlezen (tabblad Route)

1. **Maak een route in de planner** en klik op *Download JSON*. Je krijgt een bestand `….routeplan.json`.
2. **Zet het bestand op de iPhone.** Bijvoorbeeld:
   - met **AirDrop** vanaf de Mac: kies op de iPhone *Veldvlucht*, of bewaar het in *Bestanden*;
   - via **iCloud Drive**: zet het bestand in iCloud Drive op de computer.
3. **Open het in de app:** tabblad *Route* → **Routebestand openen…** → kies het bestand.
   - Wil je alleen kijken hoe het werkt? Kies **Voorbeeldroute laden**.
4. **Lees de controle.**
   - **Rood** = fout: met een fout kan de route straks niet gevlogen worden. Pas de route aan in de planner.
   - **Oranje** = waarschuwing: lees hem en beslis zelf.
   - De app controleert met de regels van de planner én met eigen regels (zie [ROUTEBESTAND.md](../docs/ROUTEBESTAND.md)). Een foto-interval onder 2 s is in de app altijd een fout.
5. **Toon op de kaart:**
   - geel = stukken met foto's;
   - oranje gestippeld = stukken zonder foto's, en de weg van en naar het startpunt;
   - witte stippen = de geplande foto's.

## De veldkaart (tabblad Veldkaart)

De veldkaart toont nu **voorbeeldgegevens** voor een verzonnen broccoliveld `veld-noord` bij Dronten. Zodra het centrale systeem bestaat, komen daar de echte gegevens.

- **Bovenaan:** het weer voor vijf dagen en het **beste vliegmoment**. Een windstoot van 8 m/s of meer staat in oranje: dat is de grens van de Mavic Mini.
- **Op de kaart:**
  - **stroken** in **blauw** (genoeg water), **geel** (binnenkort water geven) of **rood** (nu water geven);
  - **paarse** markeringen: planten of plekken die aandacht nodig hebben;
  - **turquoise** druppels: de bodemvochtsensoren met hun laatste meting.
- **Tik** op een strook, markering of sensor voor de details:
  - bij een strook: **waarop het advies gebaseerd is**;
  - bij een markering: de reden en de naam van de foto;
  - bij een sensor: een grafiek van de afgelopen dagen.
- **Kaart wisselen:** rechtsboven, knop *Kaart*. Kies tussen de luchtfoto van PDOK (alleen Nederland, scherper) en de satellietkaart van Apple.
- **Je eigen plek:** de eerste keer vraagt de app of hij je locatie mag gebruiken. Dan zie je in het veld een blauwe stip.

## Het rekenpakket testen

Het rekenwerk (routebestand, controles, dataformaten) staat apart in `VeldvluchtKern`, zonder DJI- of iPhone-code. Net als `src/core` bij de planner. Daardoor kun je het testen op de Mac, zonder iPhone of simulator:

1. Ga naar de map van het pakket:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner/ios/VeldvluchtKern
   ```
2. Draai de tests:
   ```bash
   swift test
   ```

Onderaan moet staan: *Executed 31 tests, with 0 failures*. De tests lezen ook alle voorbeeldbestanden uit `docs/voorbeelden`, dus een fout in zo'n bestand valt meteen op.

## Uitslag: go of no-go

| Onderdeel | Gelukt? |
|---|---|
| Aanmelden bij DJI | |
| iPhone ↔ afstandsbediening | |
| Afstandsbediening ↔ drone | |
| Accu zichtbaar | |
| GPS-satellieten zichtbaar (buiten) | |
| Firmware 01.00.0500 | |
| Eén foto op de SD-kaart | |
| GPS in de foto (EXIF) | |

**Alles gelukt:** go. De volgende stap is de rest van stap 3: de stuurlus en de foto's uitproberen in de simulator van DJI.
**Iets mislukt:** stuur het logboek naar Claude en kijk bij "Als het misgaat" hieronder.

## Als het misgaat

| Wat je ziet | Wat je doet |
|---|---|
| Xcode: *"De DJI App Key ontbreekt"* | Vul de App Key in, zie hierboven. |
| Xcode: *"The sandbox is not in sync with the Podfile.lock"* | Draai `bundle exec pod install` in de map `ios` (zie hieronder). |
| Xcode: iets met *Signing* of *Provisioning profile* | Kies bij *Signing & Capabilities* je Personal Team. Controleer dat de iPhone met de kabel verbonden en ontgrendeld is. |
| Stap 1: *Geen internet* (DJI-code −1) | Zet wifi of 4G aan en druk op **Opnieuw proberen**. |
| Stap 1: *De App Key klopt niet* (code −2, −9 of −15) | Controleer de sleutel in `Lokaal.xcconfig`: geen spaties of aanhalingstekens, niets vergeten. Bouw daarna opnieuw met ▶. |
| Stap 1: *De Bundle ID past niet* (code −5) | De App Key hoort bij een andere Bundle ID. Die moet op developer.dji.com `nl.milanmehrzad.veldvlucht` zijn. |
| Stap 1: *Te veel toestellen* (code −7 of −16) | De sleutel is al op te veel toestellen gebruikt. Kijk op developer.dji.com of maak een nieuwe App Key. |
| *iPhone ↔ afstandsbediening* blijft rood | Is DJI Fly echt afgesloten? Probeer de kabel opnieuw, zet de afstandsbediening uit en aan, en houd Veldvlucht op de voorgrond. Werkt het in DJI Fly wel, stuur dan het logboek naar Claude. |
| *Afstandsbediening ↔ drone* blijft rood | Staat de drone aan? Werkt dezelfde combinatie in DJI Fly? |
| De fotoknop blijft grijs | De knop werkt alleen als de drone verbonden is, er een bruikbare SD-kaart in zit en de drone niet vliegt. Kijk wat er bij *SD-kaart* staat. |
| *Geen bevestiging van een nieuw bestand* | Kijk op de SD-kaart of de foto er toch staat, en stuur het logboek naar Claude. |
| DJI Fly of de afstandsbediening vraagt om een firmware-update | **Niet doen.** De iOS-SDK noemt alleen 01.00.0500. |

## CocoaPods opnieuw installeren

Dit is al gedaan op deze Mac. Je hebt het alleen nodig als `ios/Pods` of `ios/vendor` weg is, bijvoorbeeld na een verse kopie van de repository of op een andere Mac.

1. Ga naar de map `ios`:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner/ios
   ```
2. Installeer CocoaPods (de versie uit `Gemfile.lock`) in `ios/vendor`:
   ```bash
   bundle install
   ```
3. Haal de DJI-SDK binnen (de versie uit `Podfile.lock`):
   ```bash
   bundle exec pod install
   ```

**Uitleg:**

- `bundle exec` zorgt dat precies CocoaPods 1.17.0 uit deze map gebruikt wordt.
- De waarschuwing *"CocoaPods requires your terminal to be using UTF-8 encoding"* is onschuldig. Je kunt hem voorkomen door eerst `export LANG=en_US.UTF-8` te typen.
- Op deze Mac draait CocoaPods op de Ruby 2.6 die bij macOS zit. Daarom staat in `.bundle/config` de instelling `force_ruby_platform`: één onderdeel (`ffi`) wordt dan op de Mac zelf gebouwd, omdat de kant-en-klare versie Ruby 3 vraagt.

## Hoe de code in elkaar zit

| Bestand | Wat het doet |
|---|---|
| `VeldvluchtApp.swift` | Start de app met de drie tabbladen, houdt het scherm aan en start de aanmelding bij DJI. Vangt ook routebestanden op die via AirDrop of *Deel* binnenkomen. |
| `DroneTestView.swift` | Tabblad *Drone*: de vier stappen en het logboek. Bevat geen DJI-code. |
| `DroneStatus.swift` | Wat het tabblad *Drone* laat zien (accu, GPS, firmware, foto...), in gewone Swift. |
| `DJIConnection.swift` | De **enige** plek die de DJI-SDK aanroept (de "DJI-adapter" uit hoofdstuk 6.1 van [DJI-MOBILE-SDK-V4.md](../docs/DJI-MOBILE-SDK-V4.md)). |
| `RouteView.swift` | Tabblad *Route*: bestand kiezen, controle tonen, kaart. |
| `FieldMapScreen.swift` | Tabblad *Veldkaart*: weerbalk, kaart en de details na een tik. |
| `MapCanvas.swift` | De kaart (Apple MapKit) met de PDOK-luchtfoto, vlakken, lijnen en punten. |
| `SampleData.swift` | Leest de voorbeeldbestanden die in de app zitten. |
| `VeldvluchtKern/…/RoutePlanFile.swift` | Het routebestand inlezen. Andere formaten en ongeldige coördinaten worden geweigerd. |
| `VeldvluchtKern/…/RouteCheck.swift` | De controles op de route, en de eigen berekening van afstand en vliegtijd. |
| `VeldvluchtKern/…/FieldFormats.swift` | De dataformaten uit hoofdstuk 6 van [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md). |
| `VeldvluchtKern/…/FieldSummary.swift` | Sorteert en beschrijft wat de veldkaart toont. Rekent zelf geen advies uit. |
| `VeldvluchtKern/…/Geo.swift` | Afstanden en vormen op de kaart, met dezelfde formules als de planner. |
| `Info.plist` | App-instellingen: de App Key (`DJISDKAppKey`, uit `Lokaal.xcconfig`), de DJI-protocollen voor de afstandsbediening en de teksten voor de toestemmingsvragen. |

**Bewuste keuzes:**

- **Alleen de pod `DJI-SDK-iOS`.**
  - `DJIWidget` (live camerabeeld) is voor deze test niet nodig.
  - `DJIFlySafeDatabaseResource` (de Fly Safe-database meeleveren) ook niet: de SDK downloadt die database zelf bij het aanmelden.
- **Foto maken:** de app vraagt de camera eerst of hij de "platte" camerastand kent (`isFlatCameraModeSupported`).
  - Zo ja: `setFlatMode` met *PhotoSingle*.
  - Zo nee: `setMode` met *ShootPhoto* en `setShootPhotoMode` met *Single*.

  Daarna volgt `startShootPhoto`. Pas als de camera een nieuw bestand meldt (`camera:didGenerateNewMediaFile:`), telt de foto als gelukt.
- **Twee verbindingen apart** (hoofdstuk 6.4 van het DJI-document):
  - iPhone ↔ afstandsbediening: `productConnected` en `productDisconnected`;
  - afstandsbediening ↔ drone: de verbindingssleutel `DJIParamConnection`.
