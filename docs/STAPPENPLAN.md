# Stappenplan: van routeplanner naar drone, sensoren en veldkaart

Stand op 27 oktober 2026:

- **Klaar:** de routeplanner (browser-app in deze repository).
- **Haalbaarheidstest (stap 2) geslaagd op 26 oktober 2026:** de eigen app praat met de Mavic Mini.
- **De iPhone-app Veldvlucht** in [`ios/`](../ios/README.md), met vier tabbladen:
  - **Drone:** de haalbaarheidstest (stap 2), getest met de drone;
  - **Route:** **een veld tekenen in de app** (hoeken aantikken, de app maakt de vliegbanen), of een routebestand van de planner inlezen; daarna vliegen (stap 3 t/m 5);
  - **Veldkaart:** je eigen veld met sensoren, weer en wateradvies, of de voorbeeldgegevens (stap 7 t/m 9);
  - **Vluchten:** fotologs en logboeken (stap 6).
- **Het sensorkastje** (stap 8): de software staat in [`sensor/`](../sensor/README.md). Het stuurt rechtstreeks naar de cloud, of anders naar de app.
- **Het centrale systeem** (stap 9) in de cloud, in [`centraal/`](../centraal/README.md):
  - ontvangen en opslaan, weer en wateradvies elk uur;
  - accounts, en anderen laten meekijken;
  - een eerste foto-analyse op de Mac, zonder getrainde AI.

  Je installeert het zelf in een gratis Supabase-project, met één script.
- **Nog te bouwen:** een getrainde AI (na de eerste echte vluchten).
- **Wat jij nog moet testen, staat in [TESTLIJST.md](TESTLIJST.md).**

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

1. **Mac controleren:** Apple-menu → *Over deze Mac*. Noteer het **model met jaartal** (bijvoorbeeld "MacBook Pro 13-inch, 2019") en de **macOS-versie**.
   - **Apple-chip:** de nieuwste Xcode (27, vraagt macOS Tahoe 26.6 of nieuwer).
   - **Intel-chip (deze MacBook):** Xcode 27 draait niet op Intel. Kies een oudere Xcode die past bij je macOS (bron: <https://developer.apple.com/support/xcode/>):

     | Jouw macOS | Bruikbare Xcode |
     |---|---|
     | Tahoe 26.2 of nieuwer (op Intel alleen MacBook Pro 16-inch 2019 en 13-inch 2020 met vier Thunderbolt-poorten) | 26.4.1 t/m 26.6, of 16.4 tot en met Tahoe 26.1 |
     | Sequoia 15.6 of nieuwer | 26.0 t/m 26.3, of 16.4 |
     | Sequoia 15.3 tot 15.6 | 16.4 |
     | Sonoma 14.5 tot Sequoia 15.x | 16.0 t/m 16.2 |

   - **Advies voor de DJI-SDK: Xcode 16.x** (iOS 18-SDK). Daarmee speelt de bouwfout met de iOS 26-SDK (`ALAssetsLibrary`, GitHub-issue #560) niet.
   - **Deze MacBook:** MacBook Pro 13-inch 2018 (vier Thunderbolt 3-poorten), macOS Sequoia 15.7.4. Dit model krijgt geen macOS Tahoe.
     - Gebruik **Xcode 16.4**.
     - Lukt dat niet, dan als reserve Xcode 26.3.
     - Er is 104 GB vrij; dat is genoeg voor Xcode.
   - **iPhone:** iPhone 13 met iOS 27.0.1.
   - Volgens Apple's tabel kunnen al deze versies apps installeren op iPhones met iOS 15 of nieuwer. **Test dat als eerste** met een leeg app-project op je iPhone 13.
   - Een App Store-versie kan op deze manier niet (die eist Xcode 26 of nieuwer), maar dat was door de MFi-regels toch al geen optie.
2. **Xcode installeren.**
   - **Apple-chip:** uit de Mac App Store.
   - **Intel-Mac:** de passende oudere versie, als `.xip`-bestand, van Apple's officiële downloadpagina <https://developer.apple.com/download/all/> (inloggen met je Apple ID).

   Open Xcode één keer en log in met je Apple ID (Xcode → Settings → Accounts).

   **Eerste test: werkt Xcode 16.4 met je iPhone?** Dit is de eerste go/no-go-check.

   1. Verbind de iPhone met een kabel met de Mac en tik op de iPhone op **Vertrouw**.
   2. Maak in Xcode een leeg project: *File → New → Project → iOS → App*.
   3. Kies bij *Signing & Capabilities* je Apple ID als *Team*.
   4. Kies je iPhone als doel en klik op ▶ (Run).
   5. Zet op de iPhone de **ontwikkelaarsmodus** aan als daarom gevraagd wordt (Instellingen → Privacy en beveiliging → Ontwikkelaarsmodus). Vertrouw daarna je ontwikkelaarsprofiel (Instellingen → Algemeen → VPN en apparaatbeheer).

   Verschijnt de lege app op de iPhone, dan werkt het. Zo niet, probeer dan Xcode 26.3.

   **Resultaat 25 oktober 2026: geslaagd.**
   - Xcode 16.4 op de MacBook Pro 2018 zet een lege SwiftUI-app op de iPhone 13 met iOS 27.0.1.
   - Daarvoor moest eerst het onderdeel "iOS 18.5" in Xcode gedownload worden (knop *Get*).
   - Ingelogd met een gratis Apple ID (Personal Team), organisatie-id `nl.milanmehrzad`.

   Met een gratis Apple ID werkt dit ook. De app op de iPhone verloopt dan wel na ongeveer een week; daarna installeer je hem opnieuw vanuit Xcode.
3. **DJI-ontwikkelaarsaccount** maken op <https://developer.dji.com>. De App Key volgt in stap 2, als de app een Bundle ID heeft.
4. **Hardware testen met DJI Fly:**
   - Maakt je iPhone verbinding met de afstandsbediening van de Mavic Mini?
   - Zie je het camerabeeld?
   - De iPhone 13 heeft Lightning; de gemelde problemen met USB-C-iPhones spelen hier niet. Noteer de iOS-versie (Instellingen → Algemeen → Info).
   - De firmware van de drone is **01.00.0500**, precies de versie die de iOS-SDK noemt. **Werk de firmware niet bij**, ook niet als DJI Fly erom vraagt.
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

**Voorbereiding:**

- **Kies de definitieve naam en Bundle ID**, bijvoorbeeld app **Veldvlucht** met Bundle ID `nl.milanmehrzad.veldvlucht`.
- **Maak een App Key** op developer.dji.com (User Center → Apps → Create App, platform iOS) met **exact** die Bundle ID. De App Key werkt alleen met die Bundle ID.
- **Zet de App Key niet in git.** Bewaar hem in een apart bestand dat in `.gitignore` staat.

**Gedaan (25 oktober 2026):**

- DJI-developeraccount aangemaakt.
- App **Veldvlucht** geregistreerd: Mobile SDK, iOS, Bundle ID `nl.milanmehrzad.veldvlucht`.
- De App Key staat bij de gebruiker op de Mac, niet in deze repository.

**Voor de fototest op de grond:**

- Accu's van de drone en de afstandsbediening opladen.
- **Propellers eraf.**
- Er moet een **microSD-kaart in de drone** zitten, anders kan hij geen foto opslaan.
- Sluit DJI Fly af voordat je de eigen app gebruikt.

Bouw een minimale iPhone-app die **alleen**:

1. zich aanmeldt bij DJI (`DJISDKAppKey` in Info.plist, `registerAppWithDelegate:`);
2. verbinding maakt met de drone (`startConnectionToProduct`, `productConnected:`);
3. accu, GPS-satellieten en de firmwareversie toont;
4. **op de grond één foto maakt** met de camera van de drone.

Vlieg hierbij nog niet.

**Gebouwd (25 oktober 2026):** de app **Veldvlucht** staat in [`ios/`](../ios/README.md).

- Met DJI Mobile SDK 4.16.2 via CocoaPods 1.17.0. CocoaPods is alleen in `ios/vendor/` geïnstalleerd, zonder beheerderswachtwoord.
- Gebouwd zonder fouten met Xcode 16.4.
- De App Key staat in `ios/Config/Lokaal.xcconfig`. Dat bestand staat in `.gitignore`.
- De handleiding en de go/no-go-lijst staan in [ios/README.md](../ios/README.md).

**Test met de drone (26 oktober 2026): go.**

- Opstelling: de Mavic Mini (firmware niet bijgewerkt), iPhone 13 met iOS 27.0.1, app gebouwd met Xcode 16.4.
- De uitslag per onderdeel, uit de logboeken van twee testrondes:

  | Onderdeel | Uitslag |
  |---|---|
  | Aanmelden bij DJI met de App Key | Gelukt, binnen 1 seconde |
  | iPhone ↔ afstandsbediening (Lightning-kabel) | Gelukt |
  | Afstandsbediening ↔ drone | Gelukt; de SDK herkent de drone als "Mavic Mini" |
  | Eén foto op de grond | Gelukt: `DJI_0096.jpg`, 4,0 MB op de SD-kaart, 1 seconde na de knop |
  | Accu | Gelukt: 91 % (8,10 V) |
  | GPS (buiten) | Gelukt: 10 satellieten na ongeveer 2 minuten |
  | Firmware | Gelukt: pakket **01.00.0500**, zoals verwacht; vluchtcomputer 03.04.06.43. DJI's server geeft de pakketversie dus nog door. |
  | GPS in de foto (EXIF) | Nog te controleren op de Mac (de testfoto is binnen gemaakt) |

- **Wat dit betekent:** de grootste risico's uit het onderzoek blijken geen probleem:
  - de oude SDK 4.16.2 bouwt met Xcode 16.4;
  - hij draait op iOS 27.0.1;
  - DJI accepteert de App Key nog;
  - de iPhone praat via de kabel met de afstandsbediening;
  - de app kan de camera bedienen.
- **Fout in de app, gevonden in de eerste ronde en hersteld:**
  - Het lampje *afstandsbediening ↔ drone* werd al groen toen alleen de afstandsbediening er was. Het signaal `DJIParamConnection` is dan al "verbonden".
  - Daardoor las de app de firmware te vroeg en daarna niet meer.
  - De app kijkt nu naar de vluchtcomputer van de drone. In de tweede ronde lukte de firmware daarmee meteen.
- **Nog te doen:** een foto die buiten gemaakt is op de Mac bekijken op GPS-gegevens (*Extra → Toon info* in Voorvertoning).
- **Volgende stap:** de rest van stap 3, de stuurlus in de simulator van DJI.

- **Lukt dit:** de rest is gewoon werk.
- **Lukt het niet:** kijk naar de alternatieven in hoofdstuk 7 van het DJI-document. Mogelijke oorzaken:
  - bouwproblemen met de oude SDK en de huidige Xcode (zie GitHub-issue #560 van de DJI-SDK);
  - de iPhone-verbinding;
  - de App Key.

## Stap 3: route en foto's, zonder te vliegen

**Nieuw (26 oktober 2026): een veld tekenen in de app.** Tik op de kaart de hoeken van je veld aan; de app maakt meteen de vliegbanen en de foto's. Dat rekent hij precies zo uit als de routeplanner: getest met drie velden die de planner zelf maakte. De planner op de computer is daardoor niet meer nodig, maar werkt nog wel.

- Het `.routeplan.json` inlezen (AirDrop of de Bestanden-app), opnieuw valideren en op een kaart tonen.
  - **Gebouwd (26 oktober 2026):** tabblad *Route* in de app.
  - De app gebruikt de regels van de planner, plus eigen controles op het blok `derived` dat hij straks vliegt.
  - Strenger dan de planner: een foto-interval onder 2 s is in de app een **fout**.
  - De regels staan in `ios/VeldvluchtKern` en worden getest met `swift test` (zie [ios/README.md](../ios/README.md)).
- Een stuurlus van ongeveer 10 Hz met Virtual Stick en het fotomoment per fotopositie uitproberen in de **ingebouwde simulator van de DJI-SDK**. Haal de propellers eraf als de drone voor de simulator aangesloten is.
- Testen in de simulator:
  - Klopt de vliegrichting (pitch/roll)?
  - Worden de foto's op de goede plekken gemaakt?
  - Gaat hervatten na een pauze goed?

**Gebouwd (26 oktober 2026):** de knop *Vliegen in de simulator…* op het tabblad Route.

- Elke vlucht begint met een **richtingtest**. De app meet zelf welke kant pitch en roll de drone op sturen, in plaats van op DJI's tekst te vertrouwen. Dat beantwoordt de eerste vraag bij elke vlucht opnieuw.
- **Stuurlus:**
  - 10 keer per seconde;
  - snelheid langs de lijn en remmen voor elk routepunt;
  - bijsturen naar de lijn, ook bij wind;
  - de neus langs de vliegbanen.
- **Foto's:** een losse foto bij elke geplande positie, met minstens 2 s ertussen. Een foto telt pas als de camera het bestand meldt. Het fotolog (`veld/fotolog`) staat per vlucht in de Bestanden-app.
- **Alleen in de simulator:** zonder actieve simulator start de route niet.
- **Getest met een nep-drone** (nu 120 tests in `ios/VeldvluchtKern`, na een onafhankelijke review met zes herstelde fouten):
  - de hele voorbeeldroute, met alle 180 foto's binnen 2 m van hun plek;
  - verwisselde assen en zijwind;
  - pauze en hervatten, overnemen en verbindingsverlies.
- **Nog te doen:** dezelfde test met de echte drone in de simulator van DJI. De stappen staan in [ios/README.md](../ios/README.md), "Vliegen in de simulator".

## Stap 4: veiligheid

**Stand 26 oktober 2026:** de punten hieronder zitten al in de vluchtlogica van stap 3. Ze zijn getest met de nep-drone, maar nog niet met de echte drone. Daarna volgt de test op een veilige plek, en daarna pas buiten:

- de drie knoppen;
- overnemen bij stickbewegingen;
- failsafe GoHome met een terugkeerhoogte van minstens 20 m;
- naar huis bij een bijna lege accu (DJI's schatting + 10 procentpunt, of DJI's "ernstig laag");
- nooit automatisch hervatten;
- de eigen terugkeer van de drone volgen in plaats van ertegenin sturen;
- naar huis bij een melding van zeer harde wind.

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

**Gebouwd (26 oktober 2026), nog niet getest:**
- **Echt vliegen wordt vrijgegeven** na een simulatorvlucht tot het eind en een geteste overname met een stick, op dezelfde iPhone.
- **Strengere controles:** GPS, thuispunt, accu minstens 50 %, geen windwaarschuwing en de simulator uit.
- **Korte routes:** tot 800 m, totdat 3 echte vluchten klaar zijn.
- **Controlelijst** vóór het opstijgen.
- **Meerdere accu's:** een volgende vlucht gaat verder vanaf de eerste foto die nog niet gemaakt is.

## Stap 6: foto's naar het centrale systeem

- Foto's van de microSD-kaart kopiëren, samen met het fotolog van de app.
- Het fotolog volgt het formaat `veld/fotolog` uit hoofdstuk 6 van [ARCHITECTUUR.md](ARCHITECTUUR.md).
- Bewaar foto's en fotolog per vlucht in een eigen map.

**Gebouwd (26 oktober 2026):**
- De app bewaart per vlucht het fotolog (`….fotolog.json`) en het logboek (`….logboek.txt`).
- Het tabblad *Vluchten* toont ze en kan ze delen, bijvoorbeeld met AirDrop naar de Mac.
- Ze staan ook in de Bestanden-app: *Op mijn iPhone → Veldvlucht → Vluchten*.

**Erbij gekomen (27 oktober 2026):**
- Ben je ingelogd, dan gaat het fotolog vanzelf naar het centrale systeem.
- De foto's zelf blijven op de Mac. Het programma `foto-analyse` zoekt daarin de planten die aandacht nodig hebben, en zet hun plek in de cloud. Hoe: [`centraal/README.md`](../centraal/README.md), "De foto-analyse op je Mac".

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

**Gebouwd (26 oktober 2026):**

- Stap 1 en 2: de voorbeeldbestanden staan in [`docs/voorbeelden/`](voorbeelden/). Het tabblad *Veldkaart* in de app toont ze:
  - luchtfoto van PDOK;
  - stroken in blauw, geel of rood;
  - markeringen en sensoren: tik erop voor de reden, de foto-naam of het verloop;
  - weerbalk met het beste vliegmoment.
- Nieuw dataformaat `veld/weer` voor de weerbalk (hoofdstuk 6 van [ARCHITECTUUR.md](ARCHITECTUUR.md)).
- **Nog te doen:**
  - stap 3: testen in het veld;
  - ~~echte gegevens van het centrale systeem~~: gebouwd (27 oktober 2026), als je bent ingelogd;
  - terugkijken naar eerdere datums.
- **Erbij gekomen:** eigen bestanden laden in de veldkaart (*Gegevens → Eigen bestand laden…*), bijvoorbeeld zelf gemaakte resultaten of sensormetingen.

## Stap 8: sensorkastje

**Gebouwd (26 oktober 2026), nog niet getest met een echt bordje:**
- De software voor een ESP32-bordje staat in [`sensor/`](../sensor/README.md), met een handleiding voor het aansluiten en uploaden.
- Het kastje meet elk uur, zet de sensor alleen aan tijdens het meten, en bewaart de metingen.
- Het stuurt ze via de **hotspot van de iPhone** naar de app (het formaat `veld/sensorupload` uit [ARCHITECTUUR.md](ARCHITECTUUR.md)).
- *27 oktober 2026:* het stuurt ze eerst **rechtstreeks naar de cloud**, met een geheime sleutel per sensor. Lukt dat niet, dan naar de app.
- In de app plaats je de sensoren op je veld en ijk je ze met droge en natte grond.
- Getest: het ontvangen in de app, met nep-metingen vanaf de Mac (`sensor/nep-sensorkastje.py`).

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

**Versie 0 gebouwd (26 oktober 2026)**, in de iPhone-app, zonder server en zonder account:
- **ontvangen en opslaan** van de sensormetingen, per veld;
- **tonen op de veldkaart**, met het verloop per sensor;
- **weer koppelen** via Open-Meteo, met het beste vliegmoment en een melding;
- **wateradvies met eenvoudige regels** per strook van 24 m langs de vliegbanen. Bij elk advies staat waarop het gebaseerd is.

**In de cloud gebouwd (27 oktober 2026)**, in [`centraal/`](../centraal/README.md), met Supabase:
- een database met je velden, sensoren, metingen, weer, vluchten en advies;
- **accounts**: inloggen in de app, en anderen laten meekijken met een veld;
- de sensorkastjes sturen er **rechtstreeks** naartoe;
- **elk uur** weer en wateradvies, en meteen na nieuwe metingen;
- **foto-analyse op de Mac**, zonder getrainde AI (niveau 1 uit hoofdstuk 7 van [ARCHITECTUUR.md](ARCHITECTUUR.md));
- de app synchroniseert vanzelf, en rekent zelf met dezelfde regels als hij niet is ingelogd of geen internet heeft.

De regels staan in [ARCHITECTUUR.md](ARCHITECTUUR.md), hoofdstuk 4.

- **Nog te doen:**
  - het installeren in je eigen Supabase-project (`bash centraal/installeer.sh`);
  - testen (blok F van [TESTLIJST.md](TESTLIJST.md));
  - een getrainde AI (punt 5 hieronder).

Stap voor stap, zodat elke stap zelf al nut heeft:

1. **Ontvangen en opslaan** van sensormetingen, foto's met fotolog en de veldgrens.
2. **Tonen op de veldkaart** in de app: eerst alleen de ruwe gegevens.
3. **Weer koppelen** via een officiële weerdienst (KNMI, Google Weather API of een betaald Open-Meteo-abonnement; zie [ARCHITECTUUR.md](ARCHITECTUUR.md) hoofdstuk 3).
4. **Wateradvies met eenvoudige regels**, die de teler controleert.
5. **AI**, als er genoeg gegevens en gelabelde foto's zijn:
   - wateradvies per zone;
   - het markeren van planten die aandacht nodig hebben.

De eisen staan in hoofdstuk 7 van [ARCHITECTUUR.md](ARCHITECTUUR.md):

- wateradvies per strook langs de rijrichting van de tractor;
- een melding met het beste vliegmoment;
- accounts waarmee je anderen kunt laten meekijken;
- foto-analyse op de laptop.

Daar staat ook wat nog open is.
