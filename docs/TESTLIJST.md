# Testlijst iPhone-app Veldvlucht

Stand: 26 oktober 2026. Vink af wat gelukt is (`[x]`). Lukt iets niet, druk dan op **Kopieer logboek**, plak het in een bericht aan Claude en zet erbij wat je zag. Een schermafbeelding helpt (zijknop + volume omhoog).

## Wat al getest is

- **Op de Mac, 69 automatische tests** (`swift test` in `ios/VeldvluchtKern`):
  - routebestand lezen en controleren;
  - de dataformaten en de voorbeeldbestanden;
  - de stuurlus met een **nep-drone**: de hele voorbeeldroute (alle 180 foto's binnen 2 m van hun plek), verwisselde assen, zijwind, pauze en hervatten, overnemen met de sticks, verbindingsverlies, lege accu, harde wind, de eigen terugkeer van de drone, verder vanaf een foto van een eerdere vlucht, en de strengere controles voor een echte vlucht.
- **Onafhankelijke review van de vliegcode (26 oktober 2026):** een tweede Claude las de vliegcode na en vond zes fouten. Alle zes zijn hersteld, en elk heeft nu een eigen nep-drone-test:
  - vóór de richtingtest kon de drone wegdrijven als de assen andersom zitten;
  - een late bevestiging van Virtual Stick kon een overname ongedaan maken;
  - "naar huis" kon na overnemen alsnog verstuurd worden;
  - een mislukte overname werd niet opnieuw geprobeerd;
  - één gemiste camerabevestiging liet het fotolog opschuiven;
  - zonder GPS ging hervatten terug naar het begin van de route.
- **Met de drone (stap 2, geslaagd):** aanmelden, verbinding, accu, GPS, firmware en één foto op de grond.
- **Het nieuwe ontwerp (26 oktober 2026), bekeken op je iPhone:** de app liep zelf langs alle schermen met voorbeeldgegevens en de nep-drone, in licht en donker (de "schermtour", zie [ios/README.md](../ios/README.md)). Zo zijn ook het vluchtscherm tijdens een vlucht, na een pauze, na overnemen en aan het eind bekeken.
- **Nog nooit getest:** alles met de echte drone in de simulator van DJI; echt vliegen; jouw eigen indruk van de schermen.

**Let op:** met een gratis Apple ID werkt de app een week. Daarna zet je hem opnieuw op de iPhone (▶ in Xcode, of vraag het Claude).

## A. Zonder drone (binnen, ongeveer 10 minuten)

- [ ] **A1** De app opent met onderaan vier tabbladen: *Drone*, *Route*, *Veldkaart* en *Vluchten*.
  - Op het beginscherm van de iPhone staat het nieuwe icoon: een groen veld met witte vliegbanen en een drone.
- [ ] **A2** *Route* → **Voorbeeldroute laden**. Je hoort dit te zien:
  - vier tegels: *Afstand* 2,52 km (20 routepunten), *Vliegtijd* 12:04 min, *Foto's* 180 en *Hoogte* 30 m;
  - een groene kaart *Route is in orde*;
  - onderaan de groene knop **Vliegen in de simulator…**
- [ ] **A3** *Route* → tik op het kaartje bovenaan (**Toon op de kaart**). Je hoort dit te zien:
  - de luchtfoto met 10 gele banen, oranje stippellijnen en witte stipjes;
  - een blauw huisje en een groene vlag.
  - Wissel met *Kaart* rechtsboven naar Apple en terug.
- [ ] **A4** Een eigen route uit de planner:
  1. Klik in de planner op *Download JSON*.
  2. Zet het bestand op de iPhone, met AirDrop of via iCloud Drive.
  3. Open het: *Route* → **Routebestand openen…**
  4. Probeer het ook via de Bestanden-app: houd het bestand ingedrukt → *Deel* → *Veldvlucht*.
- [ ] **A5** Open een willekeurig ander JSON-bestand. Er hoort een duidelijke rode melding te komen, en geen crash.
- [ ] **A6** *Veldkaart*. Je hoort dit te zien:
  - de weerbalk met het beste vliegmoment;
  - 5 stroken (blauw, blauw, geel, geel, rood), 3 paarse markeringen en 3 turquoise druppels.
- [ ] **A7** Tik op een strook (*Waarop gebaseerd*), een druppel (grafiek) en een paarse markering (reden).
- [ ] **A8** De app vraagt om je locatie. Kies *Bij gebruik van app*: op de kaart hoort een blauwe stip te staan waar je bent.
- [ ] **A9** *Veldkaart* → tik op **Voorbeeldgegevens**, onder de naam van het veld:
  - kies **Eigen bestand laden…** en neem een bestand uit `docs/voorbeelden`. Onder de naam staat dan *Eigen gegevens: …*;
  - kies daarna **Voorbeeldgegevens gebruiken**.
- [ ] **A10** *Vluchten* toont nog *Nog geen vluchten*.
- [ ] **A11** Buiten in de zon: is de veldkaart in één oogopslag te lezen? (stap 7, punt 3) En de tegels op het tabblad *Drone*?
- [ ] **A12** Zet de iPhone op donker (*Instellingen → Weergave en helderheid → Donker*). Is alles nog goed te lezen? Zet hem daarna terug zoals je wilt.

## B. Drone op tafel, zonder simulator (propellers eraf)

- [ ] **B1** *Drone*:
  - de lijn tussen *Afstandsbediening* en *Drone* wordt pas groen als de **drone** aan staat, niet al bij alleen de afstandsbediening;
  - je ziet de tegels *Accu*, *GPS* (satellieten en signaalstreepjes), *SD-kaart* en *Motoren*;
  - bij *Firmware*: **01.00.0500** met *Zoals verwacht*, en een regel *Vluchtcomputer*.
- [ ] **B2** Maak buiten één foto met *Maak één foto*. Bekijk hem op de Mac in Voorvertoning (*Extra → Toon info*): staat er GPS of een locatie in?
- [ ] **B3** *Route* → **Vliegen in de simulator…** zonder de simulator te starten. Je hoort dit te zien:
  - bovenaan de oranje badge *SIMULATOR UIT*;
  - onderin een oranje melding *De simulator staat uit*;
  - **Route starten** is grijs.

## C. In de simulator van DJI (stap 3), met de propellers eraf

De drone blijft op de grond. De camera maakt wel echte foto's: de voorbeeldroute geeft er 180 (ongeveer 720 MB).

- [ ] **C1** **Simulator starten**:
  - de badge wordt groen (*SIMULATOR*);
  - het rode vliegtuigje springt naar het startpunt van de route.

  Lukt dit niet, stuur dan het logboek: of de simulator van de SDK op de Mavic Mini werkt, is nog onbekend.
- [ ] **C2** **Route starten** → vink de drie punten af → **Starten**. Onderin gaan de fases voorbij: *Voorbereiden → Opstijgen → Klimmen → Richtingtest → Naar het begin → Route vliegen*.
- [ ] **C3** **Vraag 1, de richting:** wat staat er na de richtingtest in het logboek? (Bijvoorbeeld *pitch = oost, roll = noord*.) Schrijf het hier op: ____________________
- [ ] **C4** **Vraag 2, de foto's:**
  - vliegt het vliegtuigje over de gele lijnen?
  - worden de stippen **groen**, zonder rode?
  - staat de hoogte rond 30 m en de snelheid rond 4 m/s?
- [ ] **C5** **Vraag 3, hervatten:** druk midden in een baan op **Pauze** en wacht 10 seconden: hangt hij stil? Druk dan op **Hervatten**: gaat hij terug naar waar hij stopte en verder, zonder dubbele foto's?
- [ ] **C6** Druk op **Overnemen**. Je hoort te zien: *Overgenomen: jij vliegt*. Daarna hoort **Hervatten** weer te werken.
- [ ] **C7** Beweeg tijdens de route **kort een stick**. Je hoort te zien: *Je bewoog een stick: de app stuurt niet meer*. (Nodig om echt vliegen vrij te geven.)
  - Houd daarna een stick vast en druk op **Hervatten**. In het logboek hoort te staan: *Laat eerst de sticks los*.
- [ ] **C8** Druk op de **pauze/terugkeerknop van de afstandsbediening**. Wat doet de drone, en wat zegt de app? Je verwacht *De drone keert zelf terug*, zonder dat de app ertegenin stuurt.
- [ ] **C9** Trek tijdens de route **de kabel uit de iPhone** en steek hem na 10 seconden terug. Je verwacht:
  - *Overgenomen* (of *De drone keert zelf terug*);
  - de app gaat nooit vanzelf verder.
- [ ] **C10** Druk op **Naar huis**: de drone keert terug en landt (in de simulator).
- [ ] **C11** Vlieg één route helemaal af, tot *Klaar* met 180 van 180 foto's. (Nodig om echt vliegen vrij te geven.)
- [ ] **C12** **Verder met een nieuwe accu:**
  1. Start de route en druk halverwege op **Naar huis**.
  2. Sluit het vluchtscherm en open het opnieuw.
  3. Zet **Verder vanaf foto …** aan en start: begint hij bij die foto?
- [ ] **C13** *Vluchten*:
  - de simulatorvluchten staan erin, met groene stippen op de kaart;
  - **Fotolog en logboek delen** werkt met AirDrop naar de Mac;
  - in de Bestanden-app staan de vluchten onder *Op mijn iPhone → Veldvlucht → Vluchten*.
- [ ] **C14** Op de SD-kaart staan de nieuwe foto's, en de bestandsnamen kloppen met het fotolog.
- [ ] **C15** Druk op **Simulator stoppen** en zet de drone **uit en weer aan**.

## D. Eerste echte vluchten (stap 5), alleen als blok C helemaal goed ging

**Voorwaarden:**
- een open veld zonder mensen of dieren, goed weer en weinig wind;
- je bent geregistreerd als exploitant en mag daar vliegen (geen no-fly-zone, maximaal 120 m);
- je bent zelf de piloot en ziet de drone de hele vlucht;
- de **propellers zitten erop en goed vast**.

- [ ] **D1** Maak in de planner een **korte route**: 2 à 3 banen, korter dan 800 m, met het startpunt waar je staat. Zet hem op de iPhone.
- [ ] **D2** Open het vluchtscherm. De keuze **Echt vliegen** hoort te verschijnen (vrijgegeven door C7 en C11). Lees de oranje punten en los ze op:
  - minstens 10 satellieten en GPS-signaal 4;
  - het thuispunt is gezet;
  - de accu is minstens 50 %;
  - de drone geeft geen windwaarschuwing;
  - de drone staat binnen 30 m van het startpunt.
- [ ] **D3** **Echt vliegen** → vink de controlelijst af → **Alles gecontroleerd: opstijgen**. **Houd de afstandsbediening vast.** Na de richtingtest, op hoogte:
  - probeer **Pauze** en **Hervatten**;
  - probeer **Overnemen** met een stick.
- [ ] **D4** Volgt de drone de banen? Maakt hij de foto's? Landt hij weer bij het startpunt?
- [ ] **D5** Na de vlucht (stap 5, punt 2):
  1. Zet de foto's van de SD-kaart op de Mac, samen met het fotolog (*Vluchten* → *Delen*).
  2. Controleer: zijn alle geplande foto's er? Liggen ze op de goede plek? Zijn ze scherp genoeg om de planten te beoordelen? Staat er GPS in?
- [ ] **D6** Op veilige hoogte: wat doet één druk op de **pauzeknop** van de afstandsbediening? Volgens de handleiding remt de drone af. (Hoofdstuk 6.5 van het DJI-document.)
- [ ] **D7** Na 3 geslaagde echte vluchten vervalt de grens van 800 m. Ga daarna stap voor stap groter, tot een heel veld.

## Wat je naar Claude stuurt

- De logboeken van C2 t/m C12, en van elke echte vlucht.
- Het antwoord bij **C3** (richting).
- Bij D: hoeveel foto's gepland en gemaakt zijn, en of ze scherp zijn en GPS hebben.
- Alles wat er vreemd uitziet, met een schermafbeelding.
