# Veldvlucht: de iPhone-app

De iPhone-app uit [STAPPENPLAN.md](../docs/STAPPENPLAN.md). Hij heeft vier tabbladen, elk los van de andere.

**Wat je nog moet testen, met vakjes om af te vinken: [docs/TESTLIJST.md](../docs/TESTLIJST.md).**

| Tabblad | Wat het doet | Stap |
|---|---|---|
| **Drone** | De haalbaarheidstest: aanmelden bij DJI, verbinden met de Mavic Mini, accu, GPS en firmware tonen, en **op de grond één foto maken**. | 2 |
| **Route** | **Een veld tekenen**: tik de hoeken aan, de app maakt de vliegbanen. Of een routebestand van de planner inlezen. Daarna controleren, op de luchtfoto tonen en **vliegen**. | 3 |
| **Veldkaart** | Je veld met stroken in blauw, geel of rood (wateradvies), je sensoren en het weer. Of de **voorbeeldgegevens**. | 7, 8, 9 |
| **Vluchten** | Alle vluchten met hun fotolog en logboek, met een kaart en een knop om te delen (AirDrop). | 6 |

**Wat de app niet doet:**
- Hij stuurt alleen vliegcommando's **in de simulator van DJI**, of bij een **echte vlucht nadat die is vrijgegeven** (zie "Echt vliegen").
- Hij toont geen live camerabeeld.
- De fotoknop op het tabblad *Drone* werkt alleen als de drone niet vliegt.

## Wat er in deze map staat

| Bestand of map | Wat het is | In git? |
|---|---|---|
| `Veldvlucht.xcworkspace` | **Dit open je in Xcode.** Bundelt de app en de DJI-SDK. | Ja |
| `Veldvlucht.xcodeproj` | Het Xcode-project van de app. Niet los openen, maar via de workspace. | Ja |
| `Veldvlucht/` | De schermen en de DJI-koppeling (Swift), plus `Info.plist`. | Ja |
| `Veldvlucht/Assets.xcassets` | Het app-icoon (licht en donker) en de groene kleur van de app. | Ja |
| `Scripts/AppIcon.swift` | Tekent het app-icoon opnieuw, als je het wilt aanpassen (zie "Het ontwerp"). | Ja |
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

- **Een nieuw ontwerp** voor alle schermen, met een eigen app-icoon (zie "Het ontwerp").
- Het tabblad **Route** (zie "Een route inlezen" hieronder).
- Het tabblad **Veldkaart** (zie "De veldkaart" hieronder).
- Het rekenpakket `VeldvluchtKern` met tests die allemaal slagen (nu 69, zie "Het rekenpakket testen").
- De app bouwt nog steeds zonder fouten of waarschuwingen.
- **Bekeken op je iPhone:** alle schermen, in licht en donker, met de schermtour en voorbeeldgegevens (zie "Het ontwerp"). Met de echte drone zijn alleen het tabblad *Drone* en de testfoto getest. Laat het Claude weten als iets er vreemd uitziet.

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

1. **Open Veldvlucht** op de iPhone. Onderaan de bovenste kaart hoort te staan: **Aangemeld bij DJI**, met een groen vinkje.
   - Vraagt de app om je locatie of Bluetooth: kies *Sta toe bij gebruik van app*. De DJI-software gebruikt die voor de Fly Safe-regels.
2. **Zet de afstandsbediening aan** en sluit de iPhone met de kabel aan op de afstandsbediening.
   - Vraagt de iPhone om DJI Fly te openen, kies dan **Negeer**.
   - Bovenaan staan drie rondjes: *iPhone*, *Afstandsbediening* en *Drone*. De lijn tussen iPhone en afstandsbediening wordt **groen**.
3. **Zet de drone aan.** Na een tijdje wordt ook de lijn naar de *Drone* groen. Rechtsboven staat dan **Verbonden**.
4. **Bekijk de tegels:**
   - **Accu:** percentage en spanning.
   - **GPS:** het aantal satellieten en de signaalstreepjes. Buiten na een paar minuten liefst 10 of meer.
   - **SD-kaart:** hoeveel foto's er nog op passen.
   - **Firmware:** hoort **01.00.0500** te zijn, met *Zoals verwacht*. Bij een andere versie staat er *Controleer*.
5. **Druk op "Maak één foto".** Gelukt als er staat: *Gelukt: DJI_xxxx.JPG*.
6. **Druk onderaan op "Kopieer logboek"** en plak de tekst in een bericht aan Claude, of in een notitie. Daarmee staat de uitslag vast.

**Na de test:** haal de microSD-kaart uit de drone en bekijk de foto op de Mac.

- Open hem in Voorvertoning en kies *Extra → Toon info*. Staat er een tabblad met GPS of een locatie, dan zet de Mavic Mini GPS in de foto's.
- Dat zal alleen zo zijn als de drone op het moment van de foto GPS had.

## Een veld tekenen (tabblad Route)

Zo maak je een route zonder computer:

1. Ga naar het tabblad **Route** en druk op **Veld tekenen**.
2. De kaart gaat naar je eigen plek. Zoom in op je veld met twee vingers.
3. **Tik de hoeken van je veld aan**, één voor één rondom. Na drie hoeken zie je de route al:
   - gele lijnen = vliegbanen met foto's;
   - oranje stippellijnen = overgangen zonder foto's, en de weg van en naar het startpunt;
   - witte stipjes = de foto's.
4. **Aanpassen:**
   - een hoek verplaatsen: houd hem vast en sleep;
   - een hoek weghalen: tik hem aan en kies **Verwijderen**;
   - de vorige stap terugdraaien: de knop met de pijl terug.
5. **Het startpunt** (blauw huisje) zet de app op de plek waar je staat. Sleep het als de drone ergens anders opstijgt. Met **Startpunt op mijn plek zetten** zet je het weer waar je nu bent.
6. **Instellingen** (de knop met de schuifjes): vlieghoogte, baanafstand, snelheid, foto-interval, baanrichting en randmarge. De standaard is hetzelfde als in de planner: 30 m hoog, banen 20 m uit elkaar, 4 m/s, een foto elke 3 s.
7. Druk op **Bewaren** en geef het veld een naam.

**Wat er dan gebeurt:**

- De app rekent de vliegbanen **precies zo uit als de routeplanner**. Dat is getest: voor drie voorbeeldvelden van de planner geeft de app exact hetzelfde bestand (`docs/voorbeelden/voorbeeld-veld*.routeplan.json`).
- Het veld staat daarna onder **Mijn velden**. Tik erop voor de route, de controle en de knop **Vliegen in de simulator…**
- Via **⋯** rechtsboven kun je het veld **bewerken**, **verwijderen** of de **route delen** als `.routeplan.json`, bijvoorbeeld om hem in de planner op de computer te openen.
- Velden staan in de Bestanden-app onder *Op mijn iPhone → Veldvlucht → Velden*.

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
5. **Toon op de kaart:** tik op het kaartje bovenaan.
   - geel = stukken met foto's;
   - oranje gestippeld = stukken zonder foto's, en de weg van en naar het startpunt;
   - witte stippen = de geplande foto's.

## Vliegen in de simulator (stap 3)

**Wat er gebeurt:** de drone staat met de **propellers eraf** op de grond. De simulator van DJI laat de vluchtcomputer doen alsof hij vliegt, vanaf het startpunt van de route. De app stuurt de drone 10 keer per seconde met *Virtual Stick* langs de route. De camera maakt **echt** foto's op de SD-kaart: de voorbeeldroute geeft 180 foto's, samen ongeveer 720 MB.

**Veiligheid, ingebouwd in de app:**
- **Alleen in de simulator.** Staat de simulator uit, dan start de route niet. Gaat hij tijdens de vlucht uit, dan stopt de app met sturen.
- **Richtingtest.** Elke vlucht begint met een korte test op hoogte: 2 seconden alleen pitch, dan 2 seconden alleen roll. De app meet welke kant de drone op gaat. Volgens DJI is pitch = oost en roll = noord. Klopt de test niet, dan vliegt de app de route niet.
- **Sticks of Overnemen:** beweeg je een stick of druk je op **Overnemen**, dan stopt de app direct met sturen. Jij vliegt dan.
- **Verbinding weg:** de app stopt met sturen. De drone keert volgens de failsafe-instelling na 3 seconden zelf terug.
- **Accu bijna op:** de drone gaat naar huis. Wat al gelukt is, wordt bewaard.
- **Nooit vanzelf verder.** Na een pauze, overname of verbroken verbinding vraagt **Hervatten** altijd jouw bevestiging. De drone vliegt dan eerst terug naar waar de route stopte.
- **Foto's:** minstens 2 seconden tussen twee foto's. Een foto telt pas als de camera het bestand meldt.
- **De drone keert zelf terug** (lege accu, failsafe of de knop op de afstandsbediening): de app stuurt dan niet meer en laat de drone zijn gang gaan.
- **Wind:** meldt de drone zeer harde wind, dan gaat hij naar huis.
- **Landt de piloot zelf na Overnemen**, dan is de vlucht klaar en kun je het scherm sluiten.
- **Sticks:** zolang je een stick vasthoudt, start of hervat de app niet. Lukt het uitzetten van Virtual Stick niet meteen, dan probeert de app het elke seconde opnieuw. Ook **Overnemen** opnieuw indrukken helpt.
- **Vóór de richtingtest** stuurt de app geen correcties: de drone houdt zich dan met zijn eigen GPS op zijn plek.
- **Nieuwe accu:** stopt een vlucht halverwege, dan onthoudt de app de eerste foto die nog niet gemaakt is. Bij de volgende vlucht van dezelfde route kun je **Verder vanaf foto …** aanzetten.

**Zo doe je de test:**
1. Haal de **propellers eraf**. Zet de drone op een vlakke plek, met de SD-kaart erin, en sluit DJI Fly af.
2. Verbind iPhone, afstandsbediening en drone. Op het tabblad *Drone* moeten beide lijnen groen zijn.
3. Ga naar het tabblad **Route** en kies **Voorbeeldroute laden**, of je eigen route. Kies daarna **Vliegen in de simulator…**
4. Druk op **Simulator starten**. De drone "staat" dan op het startpunt van de route, met 12 GPS-satellieten.
5. In het onderste deel van het scherm mogen geen oranje punten meer staan; er staat dan *Alles klaar om te starten*. Druk op **Route starten**, vink de drie punten af en druk op **Starten**.
6. **Kijk mee.** Onderin staat de fase: *Voorbereiden → Opstijgen → Klimmen → Richtingtest → Naar het begin → Route vliegen → Naar huis en landen → Klaar*. Op de kaart vliegt het rode vliegtuigje mee. Gemaakte foto's worden **groen**, gemiste **rood**.
7. **Beantwoord de drie vragen uit het stappenplan:**
   - *Klopt de vliegrichting?* In het logboek staat na de richtingtest bijvoorbeeld "pitch = oost, roll = noord (zoals DJI beschrijft)". Vliegt het vliegtuigje over de gele lijnen?
   - *Worden de foto's op de goede plekken gemaakt?* Worden de stippen groen op de lijnen, zonder rode?
   - *Gaat hervatten na een pauze goed?* Druk midden in de route op **Pauze**, wacht even en druk op **Hervatten**. Hij hoort terug te gaan naar waar hij stopte en verder te gaan zonder dubbele foto's.
   - Probeer ook **Overnemen**, en beweeg eens kort een stick: de app moet dan stoppen met sturen.
8. **Afsluiten:**
   - Aan het eind vliegt de drone in de simulator naar huis en landt.
   - Druk op **Simulator stoppen**.
   - Zet de drone uit en weer aan voordat je ooit echt vliegt.
9. **Logboek:** de ronde knop rechtsboven (het lijstje) → **Kopieer logboek** → plak het hier in de chat.
10. **Fotolog en logboek op de iPhone:** open de Bestanden-app en ga naar *Op mijn iPhone → Veldvlucht → Vluchten*. Per vlucht staan daar:
    - het fotolog (`….fotolog.json`, formaat `veld/fotolog`);
    - het logboek (`….logboek.txt`).

**Nog niet getest:** of de simulator van de SDK op de Mavic Mini werkt. Lukt **Simulator starten** niet, stuur dan het logboek.

## Echt vliegen (stap 5)

**Pas na de simulator.** De keuze **Echt vliegen** verschijnt onderin het vluchtscherm zodra op deze iPhone twee dingen zijn gelukt:
1. een simulatorvlucht tot *Klaar*, met minstens 90 % van de foto's;
2. overnemen door een stick te bewegen tijdens een simulatorvlucht.

Tot die tijd staat er welke van de twee nog ontbreekt: een groen vinkje is gelukt, een leeg rondje nog niet.

**Strengere controles bij een echte vlucht:**
- minstens 10 GPS-satellieten en GPS-signaal 4 van 5;
- het thuispunt is gezet;
- de accu is minstens 50 %;
- de drone geeft geen windwaarschuwing;
- de simulator staat uit;
- de drone staat binnen 30 m van het startpunt van de route.

**Korte routes eerst:** tot er 3 echte vluchten klaar zijn, accepteert de app alleen routes tot 800 m, oftewel 2 à 3 banen (stap 5 van het stappenplan).

**Voor het opstijgen** toont de app een controlelijst. Pas als je alles hebt afgevinkt, werkt de knop **Alles gecontroleerd: opstijgen**:
- propellers erop;
- je ziet de drone de hele vlucht;
- geen mensen of dieren onder de route;
- wind ruim onder 8 m/s;
- je mag daar vliegen (registratie, geen no-fly-zone, maximaal 120 m);
- je houdt de afstandsbediening vast.

**Tijdens de vlucht** gelden dezelfde regels als in de simulator. **Overnemen** kan altijd: met de knop, of door een stick te bewegen.

## Vluchten (tabblad Vluchten)

- Elke vlucht met foto's staat hier, met de route, het aantal foto's, een kaart met de fotoplekken en of het een simulatorvlucht was.
- **Fotolog en logboek delen** stuurt beide bestanden, bijvoorbeeld met AirDrop naar de Mac. Zet daar de foto's van de SD-kaart in dezelfde map (stap 6). Het fotolog zegt welk bestand bij welke geplande foto hoort.
- **Verwijderen:** veeg een vlucht naar links.
- Dezelfde bestanden staan in de Bestanden-app: *Op mijn iPhone → Veldvlucht → Vluchten*.

## De veldkaart (tabblad Veldkaart)

De veldkaart toont **je eigen veld** (getekend in de app), of de **voorbeeldgegevens** van een verzonnen broccoliveld bij Dronten. Kiezen doe je door op de regel onder de naam van het veld te tikken.

**Voor je eigen veld:**

- **Het weer** haalt de app zelf op bij Open-Meteo (gratis, met bronvermelding), voor het midden van het veld. Er is internet voor nodig. De app vernieuwt het elk uur dat je de veldkaart opent.
- **Het beste vliegmoment:** minstens 2 uur achter elkaar met wind onder 5 m/s, windstoten onder 7 m/s, droog en licht.
- **Melding bij goed vliegweer:** zet die aan in het menu onder de naam van het veld. Je krijgt dan een melding een uur voor het volgende goede moment. Die wordt gepland als je de veldkaart opent; zonder app open komt er geen nieuwe.
- **Sensoren plaatsen en ijken:** in hetzelfde menu (zie "Sensoren" hieronder).
- **Wateradvies per strook** (centraal systeem, versie 0): zie "Het wateradvies" hieronder.

**Voor alle velden:**


- **Bovenaan**, in een doorzichtig paneel: de naam van het veld, het **beste vliegmoment** en het weer voor vijf dagen. Een windstoot van 8 m/s of meer staat in oranje: dat is de grens van de Mavic Mini.
- **Op de kaart:**
  - **stroken** in **blauw** (genoeg water), **geel** (binnenkort water geven) of **rood** (nu water geven);
  - **paarse** markeringen: planten of plekken die aandacht nodig hebben;
  - **turquoise** druppels: de bodemvochtsensoren met hun laatste meting.
- **Tik** op een strook, markering of sensor voor de details:
  - bij een strook: **waarop het advies gebaseerd is**;
  - bij een markering: de reden en de naam van de foto;
  - bij een sensor: een grafiek van de afgelopen dagen.
- **Kaart wisselen:** het knopje met de lagen rechtsboven in het paneel. Kies tussen de luchtfoto van PDOK (alleen Nederland, scherper) en de satellietkaart van Apple.
- **Je eigen plek:** de eerste keer vraagt de app of hij je locatie mag gebruiken. Dan zie je in het veld een blauwe stip.
- **Eigen gegevens:**
  - Tik op **Voorbeeldgegevens** onder de naam van het veld → **Eigen bestand laden…** en kies een bestand in een van de formaten uit hoofdstuk 6 van [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md): resultaten (`.geojson`), sensormetingen of weer. De app controleert het eerst.
  - Wat je niet laadt, blijft voorbeeldgegevens. Onder de naam van het veld staat dan welke gegevens van jou zijn.
  - **Voorbeeldgegevens gebruiken** zet alles terug.
  - Bij je eigen veld vervangt een resultatenbestand het berekende advies. **Berekend advies gebruiken** zet het terug.

## Sensoren

1. **Plaatsen:** Veldkaart → tik op de regel onder de naam van je veld → **Sensoren plaatsen en ijken…**
   - Kies het aantal. De app verdeelt ze over het veld, dwars op de rijrichting van de tractor.
   - Sleep een sensor (vasthouden) naar de plek waar hij echt in de grond zit.
   - Elke sensor krijgt een naam, bijvoorbeeld `broccoli-west-s1`. **Die naam zet je in het kastje.**
2. **Het kastje bouwen en instellen:** zie [sensor/README.md](../sensor/README.md).
3. **Ontvangen:**
   - Zet op de iPhone **Persoonlijke hotspot** aan, met **Maximaliseer compatibiliteit**. Het kastje werkt alleen met 2,4 GHz.
   - Houd Veldvlucht open. Het kastje stuurt zijn metingen zodra het de hotspot ziet.
   - Vraagt de iPhone of Veldvlucht apparaten op je **lokale netwerk** mag zoeken, kies dan **Sta toe**.
   - In het sensorscherm zie je wat er binnenkwam, bijvoorbeeld *Sensor s1 (Broccoli west): 3 meting(en) ontvangen*.
   - Staat de sensor in geen enkel veld, dan zegt de app dat ook. Het kastje bewaart zijn metingen dan tot je de sensor met dezelfde naam plaatst.
   - De ontvanger neemt alleen verbindingen aan van een lokaal netwerk, zoals de hotspot. Vanaf internet kan niemand metingen sturen.
4. **IJken** (nodig voor advies):
   - Steek de sensor in een bak **droge** grond van het veld en wacht op een meting. Kies dan **Laatste = droog**.
   - Doe hetzelfde met **kletsnatte** grond, en kies **Laatste = nat**.
   - Daarna toont de app de metingen als **% vocht**: 0 % is je droge grond, 100 % je natte grond.
5. **Bewaar** rechtsboven.

De metingen staan in de Bestanden-app onder *Op mijn iPhone → Veldvlucht → Velden → (je veld) → sensormetingen.json*, in het formaat `veld/sensormeting`.

## Account, cloud en delen

Het centrale systeem draait in de cloud, in Supabase. Hoe je het installeert, staat in [centraal/README.md](../centraal/README.md). Zonder cloud werkt de app ook: alles blijft dan op deze iPhone.

- **Inloggen:** tabblad *Route* → het poppetje linksboven → **Account maken** of **Inloggen**.
- **Synchroniseren** gaat vanzelf als je de app opent, en met **Nu synchroniseren**:
  - je velden en de fotologs van je vluchten gaan naar de cloud;
  - de sensormetingen, het weer en het advies van de cloud komen terug;
  - de velden die anderen met je delen, komen ook binnen.
- **Sleutels voor de kastjes:** na *Bewaren* bij *Sensoren plaatsen en ijken* staat bij elke sensor zijn sleutel (`SENSOR_SLEUTEL`). Onder het poppetje staan `CLOUD_PROJECT` en `CLOUD_SLEUTEL`.
- **Delen:** *Veldkaart* → tik op de regel onder de naam → **Delen met anderen…** → het e-mailadres van iemand met een Veldvlucht-account.
  - Die ziet het veld bij *Gedeeld met mij*, met de sensoren, het weer en het advies.
  - Kijken mag, veranderen niet. Vliegen ook niet.
- **Advies nu laten berekenen:** in hetzelfde menu. Anders gebeurt het elk uur, en meteen na nieuwe metingen.
- **Je login** staat in de sleutelhanger van de iPhone, niet in een bestand.

## Het wateradvies

Het advies komt van het centrale systeem in de cloud. Ben je niet ingelogd, of heeft de app nieuwere metingen dan de cloud, dan rekent de app het zelf uit **met dezelfde regels** (`WaterAdvisor`). Bij een strook staat waar het advies vandaan komt.

- **Stroken:** het veld wordt verdeeld in stroken van 24 m breed langs de vliegbanen. Dat is ook de rijrichting van de tractor; met de echte gegevens van de tractor kan dit later beter.
- **Per strook** kijkt het naar de sensor in die strook (of anders een sensor ernaast), en naar de regen en verdamping van vandaag en morgen.
- **De regels**, kort:
  - droger dan 35 % en weinig regen op komst → **nu water geven** (rood);
  - droger dan 35 % maar 10 mm regen of meer op komst → **binnenkort**, wacht op de regen (geel);
  - tussen 35 en 50 % → **binnenkort**, tenzij er 5 mm meer regen dan verdamping komt (dan **genoeg**);
  - 50 % of natter → **genoeg** (blauw).
- **Geen advies** (grijs) als er geen sensor in de buurt is, de sensor nog niet geijkt is, of de laatste meting ouder is dan 2 dagen. De reden staat erbij.
- **Tik op een strook** om te zien waarop het advies gebaseerd is: welke sensor, hoeveel vocht, hoeveel regen, en welke regel.
- **Het is een advies.** De regels zijn een eerste versie zonder AI. Vergelijk ze met wat je in het veld ziet.

## Het ontwerp

Sinds 26 oktober 2026 heeft de app een nieuw uiterlijk, in de stijl van iOS 26 en 27. Apple noemt die stijl *Liquid Glass*.

- **Kaarten met ronde hoeken** op een lichtgrijze achtergrond, zoals in de apps Instellingen en Gezondheid.
- **Glas boven de kaart.** Knoppen en panelen zweven boven de luchtfoto, met een matte, doorschijnende achtergrond.
  - In iOS 27 maakte Apple dat glas minder doorzichtig, zodat tekst beter te lezen is. De app doet hetzelfde: handig buiten in de zon.
- **Grote, ronde cijfers** voor accu, GPS, hoogte en snelheid: in één oogopslag te lezen.
- **Elke kleur betekent iets:**
  - groen = goed, of starten;
  - blauw = pauze;
  - oranje = let op, of overnemen;
  - rood = een probleem, of naar huis.
- **Grote knoppen**, minstens 54 punten hoog. De kleuren zijn donker genoeg voor witte tekst in de zon.
- **Licht en donker:** de app volgt de instelling van de iPhone.
- **Je voelt het:** de iPhone tikt kort als de app stopt met sturen (overgenomen of gestopt) en als een route klaar is.
- **Een eigen app-icoon:** een groen veld met vliegbanen en een drone.

**Waarom niet het echte Liquid Glass van Apple?** Dat kan pas met Xcode 26 of nieuwer, en deze Mac heeft Xcode 16.4. De app bootst het glas na met de matte lagen van iOS 18. Met een nieuwere Xcode wordt ook de tabbalk onderaan van glas.

**Alles over het uiterlijk staat in `Veldvlucht/Design.swift`.** Een kleur of knop aanpassen doe je daar, en dan verandert hij overal.

**Het icoon aanpassen:** pas de tekening aan in `Scripts/AppIcon.swift`. Maak daarna in de map `ios` het icoon opnieuw:
```bash
swift Scripts/AppIcon.swift Veldvlucht/Assets.xcassets/AppIcon.appiconset
```

**De schermtour (voor Claude).** De testversie van de app kan alle schermen zelf langslopen. Ze gebruikt dan voorbeeldgegevens en de nep-drone uit de tests, en maakt van elk scherm een afbeelding, in licht en donker. Zo kon Claude het ontwerp op je iPhone bekijken zonder simulator.
- De tour start alleen met de opstartoptie `-schermtour`. Die geeft Claude mee vanaf de Mac; jij komt hem nooit tegen.
- De tour maakt geen verbinding met de drone.
- De afbeeldingen komen in de map *Schermtour* van de app. Claude haalt ze op naar de Mac. Bij de volgende gewone start van de app verdwijnt die map weer.

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

Onderaan moet staan: *Executed 125 tests, with 0 failures*.

- De tests lezen ook alle voorbeeldbestanden uit `docs/voorbeelden`, dus een fout in zo'n bestand valt meteen op.
- **De stuurlus wordt getest met een nep-drone** (`FakeDrone.swift`): een eenvoudig model dat reageert op stuurcommando's, met een vertraging, en eventueel met wind. Daarmee vliegt de test de hele voorbeeldroute en controleert hij:
  - alle 180 foto's binnen 2 m van hun plek, en minstens 2 s tussen twee foto's;
  - verwisselde of omgekeerde assen, en een mislukte richtingtest;
  - zijwind;
  - pauze en hervatten, overnemen met de sticks, verbindingsverlies, lege accu en een simulator die uitvalt;
  - de eigen terugkeer van de drone, de failsafe, harde wind, landen door de piloot;
  - verder vanaf een foto van een eerdere vlucht, en de strengere controles van een echte vlucht;
  - de zes fouten uit de onafhankelijke review van 26 oktober 2026, elk met een eigen test (zie [TESTLIJST.md](../docs/TESTLIJST.md)).
- **Veld tekenen** (`FieldPlannerTests`): voor drie velden die de routeplanner zelf maakte, geeft de app precies hetzelfde routebestand. Ook: rechthoeken, een U-vorm, te kleine velden en een veldgrens die zichzelf kruist.
- **Weer, sensoren en advies** (`CentralTests`): een echt antwoord van Open-Meteo met de vliegmomenten, uploads van een kastje (ook dubbel verstuurd), en alle regels van het wateradvies.
- **De cloud** (`CloudTests`): inloggen, een verlopen login vernieuwen, velden bewaren met de sleutels van de kastjes, metingen lezen, en wat er gebeurt zonder internet. Tegen een nep-server.
- **De foto-analyse** (`PlantAnalysisTests`): een nagemaakte foto met een gelige en een kleine plant, en de plek op de grond bij elke vliegrichting.

**De planner op de Mac.** Node.js staat alleen in de projectmap (`.tools/node`, niet in git). Zo draai je de 71 tests van de planner:
```bash
cd ~/Documents/GitHub/drone-routeplanner
```
```bash
PATH="$PWD/.tools/node/bin:$PATH" npm test
```

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
| Aanmelden bij DJI: *Geen internet* (DJI-code −1) | Zet wifi of 4G aan en druk op **Opnieuw proberen**. |
| Aanmelden bij DJI: *De App Key klopt niet* (code −2, −9 of −15) | Controleer de sleutel in `Lokaal.xcconfig`: geen spaties of aanhalingstekens, niets vergeten. Bouw daarna opnieuw met ▶. |
| Aanmelden bij DJI: *De Bundle ID past niet* (code −5) | De App Key hoort bij een andere Bundle ID. Die moet op developer.dji.com `nl.milanmehrzad.veldvlucht` zijn. |
| Aanmelden bij DJI: *Te veel toestellen* (code −7 of −16) | De sleutel is al op te veel toestellen gebruikt. Kijk op developer.dji.com of maak een nieuwe App Key. |
| De lijn *iPhone ↔ afstandsbediening* blijft grijs | Is DJI Fly echt afgesloten? Probeer de kabel opnieuw, zet de afstandsbediening uit en aan, en houd Veldvlucht op de voorgrond. Werkt het in DJI Fly wel, stuur dan het logboek naar Claude. |
| De lijn *afstandsbediening ↔ drone* blijft grijs | Staat de drone aan? Werkt dezelfde combinatie in DJI Fly? |
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
| `VeldvluchtApp.swift` | Start de app met de vier tabbladen, houdt het scherm aan en start de aanmelding bij DJI. Vangt ook routebestanden op die via AirDrop of *Deel* binnenkomen. |
| `DroneTestView.swift` | Tabblad *Drone*: de verbinding, de tegels voor accu, GPS, SD-kaart en motoren, de firmware, de testfoto en het logboek. Bevat geen DJI-code. |
| `Design.swift` | **Het ontwerp op één plek:** kleuren, kaarten, glas boven de kaart, tegels, grote knoppen en de getekende drone. |
| `ScreenTour.swift` | Alleen in de testversie: een rondgang langs alle schermen die van elk scherm een afbeelding maakt (zie "Het ontwerp"). |
| `DroneStatus.swift` | Wat het tabblad *Drone* laat zien (accu, GPS, firmware, foto...), in gewone Swift. |
| `DJIConnection.swift` | De **enige** plek die de DJI-SDK aanroept (de "DJI-adapter" uit hoofdstuk 6.1 van [DJI-MOBILE-SDK-V4.md](../docs/DJI-MOBILE-SDK-V4.md)). Voert de commando's van de vluchtlogica uit: simulator, Virtual Stick, opstijgen, naar huis, foto. Meldt telemetrie en stickbewegingen terug. |
| `RouteView.swift` | Tabblad *Route*: je velden, een bestand kiezen, en per route de kaart, de controle en de knop naar de vlucht. |
| `FieldEditor.swift` | **Veld tekenen**: hoeken aantikken en verslepen, startpunt, instellingen. Ook de kaart waarop je sensoren versleept. |
| `FieldStore.swift` | Bewaart de getekende velden, één bestand per veld in *Velden*. |
| `SensorEditor.swift` | Sensoren plaatsen, hun naam voor het kastje, en ijken. |
| `SensorReceiver.swift` | **De ontvanger:** neemt via de hotspot de metingen van de sensorkastjes aan (poort 8787) en zet ze bij het juiste veld. |
| `WeatherService.swift` | Haalt het weer op bij Open-Meteo en plant de melding voor goed vliegweer. |
| `CloudStore.swift` | **De koppeling met de cloud:** je login (in de sleutelhanger), synchroniseren, sleutels van de kastjes, delen. |
| `AccountView.swift` | De schermen *Account en cloud* en *Delen*. |
| `FlightView.swift` | Het vluchtscherm (volledig scherm): kaart met de drone, de fase, voortgang, de knoppen Pauze, Overnemen en Naar huis, en de controlelijst voor de start. Laat de stuurlus 10 keer per seconde lopen. Bewaart fotolog, logboek en voortgang. Regelt het vrijgeven van echt vliegen. |
| `FlightsView.swift` | Tabblad *Vluchten*: opgeslagen vluchten met kaart en delen. |
| `FieldMapScreen.swift` | Tabblad *Veldkaart*: kaart over het hele scherm, het paneel met weer en gegevens, en de details na een tik. |
| `MapCanvas.swift` | De kaart (Apple MapKit) met de PDOK-luchtfoto, vlakken, lijnen en punten. |
| `SampleData.swift` | Leest de gegevens voor de veldkaart: je eigen veld met zijn metingen, weer en advies, of de voorbeeldbestanden in de app. |
| `VeldvluchtKern/…/FieldPlanner.swift` | **Vliegbanen en foto's voor een veld**, dezelfde berekening als de planner (`src/core`). |
| `VeldvluchtKern/…/FieldRecord.swift` | Een getekend veld, zijn sensoren, de stroken voor het advies en het beeld van de camera op de grond. |
| `VeldvluchtKern/…/OpenMeteo.swift` | Het weer van Open-Meteo in het formaat `veld/weer`, met de vliegmomenten. |
| `VeldvluchtKern/…/SensorUpload.swift` | Wat een kastje stuurt (`veld/sensorupload`) omzetten naar metingen, zonder dubbele. |
| `VeldvluchtKern/…/WaterAdvisor.swift` | Wateradvies per strook met eenvoudige regels (dezelfde als in de cloud: `centraal/supabase/functions/_shared/rekenkern.ts`). |
| `VeldvluchtKern/…/Cloud.swift` | Praat met Supabase: inloggen, velden, metingen, weer, advies, vluchten, delen. |
| `VeldvluchtKern/…/PlantAnalysis.swift` | **De foto-analyse:** planten vinden, afwijkende markeren, hun plek op de grond uitrekenen. |
| `VeldvluchtKern/Sources/FotoAnalyse/main.swift` | Het programma `foto-analyse` voor op de Mac (zie [centraal/README.md](../centraal/README.md)). |
| `VeldvluchtKern/…/RoutePlanFile.swift` | Het routebestand inlezen. Andere formaten en ongeldige coördinaten worden geweigerd. |
| `VeldvluchtKern/…/RouteCheck.swift` | De controles op de route, en de eigen berekening van afstand en vliegtijd. |
| `VeldvluchtKern/…/FieldFormats.swift` | De dataformaten uit hoofdstuk 6 van [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md). |
| `VeldvluchtKern/…/FieldSummary.swift` | Sorteert en beschrijft wat de veldkaart toont. Rekent zelf geen advies uit. |
| `VeldvluchtKern/…/Geo.swift` | Afstanden en vormen op de kaart, met dezelfde formules als de planner. |
| `VeldvluchtKern/…/RouteFlight.swift` | **De vluchtlogica:** de toestanden uit hoofdstuk 6.3 van het DJI-document, de stuurlus, de fotomomenten en de veiligheidsregels. Bevat geen DJI-code. |
| `VeldvluchtKern/…/FlightPlan.swift` | De route in meters rond het startpunt, voor de stuurlus. |
| `VeldvluchtKern/…/AxisMapping.swift` | De richtingtest: welke kant pitch en roll de drone op sturen. |
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
