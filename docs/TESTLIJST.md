# Testlijst iPhone-app Veldvlucht

Stand: 9 november 2026. Vink af wat gelukt is (`[x]`). Lukt iets niet, druk dan op **Kopieer logboek**, plak het in een bericht aan Claude en zet erbij wat je zag. Een schermafbeelding helpt (zijknop + volume omhoog).

## Wat al getest is

- **Op de Mac, 135 automatische tests** (`swift test` in `ios/VeldvluchtKern`):
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
- **Veld tekenen, weer en advies (26 oktober 2026, avond):**
  - de app maakt voor drie voorbeeldvelden exact dezelfde route als de routeplanner;
  - het weer van Open-Meteo, met de vliegmomenten;
  - alle regels van het wateradvies;
  - ontvangen van metingen: getest op je iPhone met nep-metingen die de Mac via wifi stuurde.
- **Het centrale systeem in de cloud (27 oktober 2026), alleen op de Mac:**
  - de database in een echte Postgres op de Mac (PGlite): wie wat mag zien, delen, sleutels van de kastjes, metingen zonder dubbele;
  - het programma van elk uur tegen een nep-database, en dat de cloud precies hetzelfde advies geeft als de app;
  - de koppeling in de app tegen een nep-server: inloggen, synchroniseren, geen internet;
  - de foto-analyse met nagemaakte foto's: hij vond precies de ene gelige plant, op de goede plek.
- **Het centrale systeem in je eigen Supabase-project (1 november 2026):**
  - account, veld, weer en advies komen in de cloud en terug in de app;
  - nep-metingen komen binnen, en dubbel versturen telt één keer;
  - zonder login kun je geen velden lezen, en een verkeerde sleutel wordt geweigerd.
- **Eerste vlucht in de simulator van DJI (2 november 2026):** je eigen veld *Vliegtest #1* (5 foto's). Opstijgen, richtingtest, route en landen gingen goed: 5 van 5 foto's op 30 m. Twee fouten gevonden en hersteld:
  - de tegel *SD-kaart* sprong heen en weer tussen vol en vrij: de drone meldt ook een "interne opslag" die de Mavic Mini niet heeft, en die meldingen negeert de app nu;
  - **Overnemen** tijdens het naar huis gaan zei "jij vliegt", terwijl de drone dat weigerde (time-out), en sprong dan terug naar "De drone keert zelf terug". Nu zegt de app pas "jij vliegt" als de drone het accepteert, gebruikt hij tijdens het landen *landen afbreken*, en zegt hij eerlijk als het niet lukt. Vier nieuwe nep-drone-tests.
- **Tweede ronde in de simulator (2 november 2026, 9:23 tot 9:34):** pauze, Overnemen en de stick-test werkten, en de melding *De drone hangt net boven de grond en wacht* verscheen. Wat de app daarna beter doet:
  - stopt de drone zelf met terugkeren (bijvoorbeeld door de pauzeknop van de afstandsbediening), dan zegt de app na 3 s *De drone keert niet meer terug … Jij vliegt*;
  - land je zelf met de linkerstick omlaag, dan heet dat niet meer *De drone keert zelf terug*;
  - twee keer steeg de drone niet op (*Verder vanaf foto 3*), zonder foutmelding. Nu schrijft de app daarbij op of de drone het commando aannam, of de motoren draaiden en in welke vluchtstand hij stond.
  Drie nieuwe nep-drone-tests.
- **Landen op 0,5 m:** de drone bleef net boven de grond hangen, ook met de linkerstick omlaag. Nu verschijnt dan een groene knop **Landen** (DJI's *landen bevestigen*). Eén nieuwe nep-drone-test.
- **Derde ronde in de simulator (5 november 2026):** je veld *Vliegtest #2* (18 foto's) in twee vluchten. Halverwege **Naar huis** (7 foto's), daarna **Verder vanaf foto 8** (11 foto's): samen 18 van 18, niets gemist. Beide keren landde hij met de knop **Landen**, 4 seconden na het tikken.
- **Logboek uitgebreid (5 november 2026):** C8 en C9 waren niet terug te vinden in het logboek. Nu schrijft de app in elke fase in de lucht op wanneer de verbinding wegvalt en terugkomt, en elke nieuwe vluchtstand van de drone (bijvoorbeeld *Joystick*, *GoHome*, *AutoLanding*). Eén nieuwe nep-drone-test.
- **Voorbeeldroute in de simulator (5 november 2026, 23:53):** 91 van de 180 foto's, niets gemist. Toen was de accu op 31 % en ging de drone volgens de regels naar huis. Een tweede vlucht vanaf foto 92 begon met dezelfde lege accu en keerde na een minuut om. In de simulator start de app nu pas vanaf 40 % accu. Tijdens het terugkeren trok je de kabel eruit; na 19 seconden stond de drone "op de grond" in vluchtstand *GPS*. Waarschijnlijk stopte de simulator bij het loskoppelen, en dat schrijft de app voortaan op. Twee nieuwe nep-drone-tests.
- **Camera recht naar beneden (6 november 2026):** de app draaide de camera nergens naar beneden. De foto's waren dan schuin vooruit genomen, en de foto-analyse rekent met een camera die recht naar beneden kijkt. Nu draait de app de camera vóór het opstijgen naar −90°; lukt dat niet, dan stijgt hij niet op. Staat de camera tijdens de route meer dan 5° scheef (bijvoorbeeld door het wieltje op de afstandsbediening), dan zet de app hem terug en schrijft dat op. Drie nieuwe nep-drone-tests.
- **Vierde ronde in de simulator (6 november 2026):** nog met de versie van vóór *camera recht naar beneden*.
  - De hele voorbeeldroute in één vlucht (9:25 tot 9:37): **180 van 180 foto's**, niets gemist, op 30 m. Daarna naar huis en landen met **Landen**.
  - *Vliegtest #2*: pauze en hervatten goed. Daarna de kabel eruit (C9): de app nam over en ging niet vanzelf verder. Na 23 s stond de simulator uit en de drone weer op de grond. Dat is nu twee keer gezien: **de kabel lostrekken stopt de simulator van DJI**. Wat de echte drone dan doet, kan de simulator dus niet laten zien.
  - De foto's in het fotolog lopen door zonder gaten. Eén foto (DJI_0413) vroeg de app niet; die staat terecht niet in het fotolog.
  - Wat de app nu beter zegt: bij een losse kabel *Kabel tussen iPhone en afstandsbediening los* (en niet meer dat de drone na 3 s terugkeert, want dat geldt alleen als de radioverbinding tussen afstandsbediening en drone wegvalt), en bij een gestopte simulator *De simulator is gestopt* in plaats van *Geland door de piloot*. Eén nieuwe nep-drone-test.
- **Vijfde ronde in de simulator (6 november 2026, 9:55 tot 10:01), met *camera recht naar beneden*:** daarmee is **blok C af**.
  - Beide vluchten begonnen met *Camera recht naar beneden.*
  - C8: na de knop met het huisje op de afstandsbediening keerde de drone zelf terug, en de app stuurde niet meer.
  - C16: je draaide zes keer aan het wieltje; de app zag het elke keer en draaide de camera terug. Maar die zes foto's werden toch gemaakt en telden mee. Een scheve foto ligt meters naast de plek en zet planten op de verkeerde plaats op de kaart. Nu slaat de app een foto over zolang de camera scheef staat. Omdat de foto's elkaar overlappen, blijft de grond toch helemaal in beeld.
  - **Landen** werd twee keer kort na elkaar getikt, en beide tikken gingen naar de drone. Nu verdwijnt de knop na één tik.
  - Eén stick bewogen tijdens de richtingtest: de app gaf de besturing meteen terug, en **Hervatten** werkte.
- **Eerste echte vlucht (6 november 2026, 11:34 tot 11:36):** *Echte vlucht test #1*, 4 foto's.
  - Camera recht naar beneden, opstijgen, de route, **4 van 4 foto's** op 30 à 30,5 m, precies 12 m uit elkaar en met de neus langs de baan (156°). Daarna naar huis en zelf geland, zonder te wachten op 0,5 m zoals in de simulator.
  - De **eerste richtingtest mislukte** (*met alleen pitch bewoog de drone schuin, 48°*); de route startte dus niet, zoals bedoeld. Na **Hervatten** lukte hij wel. De oorzaak is waarschijnlijk GPS: een echte GPS-positie zwalkt een halve tot een hele meter, en de test bewoog maar 2 m. Nu beweegt de test 3 s met 2 m/s (zo'n 6 m per richting), en meet hij de wind aan de snelheid die de drone zelf meldt in plaats van aan twee GPS-posities. Het logboek schrijft ook op wat hij precies mat (*Gemeten: pitch … m naar …°*). Eén nieuwe nep-drone-test met zwalkende GPS.
- **Tweede en derde echte vlucht (6 november 2026, 11:48 en 11:51):** dezelfde route.
  - De nieuwe richtingtest lukte **beide keren meteen** (gemeten: pitch 5,5 en 6,2 m naar het oosten, roll 6,7 en 5,9 m naar het noorden, binnen 7° van de as).
  - Pauze, Hervatten, Overnemen met de knop en met een stick werkten allemaal. Bij beide overnames meldde DJI eerst een fout (−1008) bij het uitzetten van Virtual Stick, maar de drone stond al in vluchtstand *GPS*, dus jij had meteen de besturing; de tweede poging lukte een seconde later.
  - De knop met het huisje: de drone ging zelf naar huis (*GoHome*) en de app stuurde niet meer.
  - Vijf keer stond de camera even op −80° tot −83°, telkens bij afremmen of optrekken, zonder dat het wieltje werd aangeraakt. De app wachtte dan met de foto: **geen enkele foto gemist**, één foto lag 2 m later dan gepland. Het bericht zegt nu *De camera kijkt even niet recht naar beneden … De app wacht met de foto*.
  - In de derde vlucht vloog de drone met de neus naar achteren (335°); de app kiest de kant die het minst draaien kost. Dat mag: het fotolog bewaart de richting.
- **De foto's van de drie echte vluchten bekeken (6 november 2026, D5):** DJI_0440 tot en met DJI_0450, gekopieerd naar *echte-vlucht-1* op het bureaublad.
  - Alle 11 foto's zijn er, en de GPS-positie in elke foto is gelijk aan die in het fotolog (binnen een halve meter).
  - Scherp genoeg: op ware grootte zie je losse grassprieten en blaadjes van een paar centimeter. Sluitertijd 1/160 tot 1/200 s bij ISO 100; bij 4 m/s is dat 2 à 2,5 cm beweging, ongeveer 2 pixels. Een broccoliplant is tientallen pixels breed.
  - **De foto's waren 16:9** (4000 × 2250) in plaats van 4:3 (4000 × 3000). Dan dekt een foto een kwart minder grond dan de planner rekent. Nu zet de app de camera vóór het opstijgen op 4:3.
  - **De camera stond in 6 van de 11 foto's 5 tot 8,5° scheef**, telkens vlak na optrekken of afremmen: de drone kantelde dan tot 20°, en de camera liep achter. In de eerste vlucht, zonder pauzes, stond hij steeds op −90°. Nu bouwt de app de snelheid rustig op (hooguit 1 m/s per seconde); afremmen blijft even snel. Eén nieuwe nep-drone-test.
  - Er zaten twee mensen op een bankje onder de route.
- **Vierde echte vlucht (9 november 2026, 08:41 tot 08:44):** 17 foto's, DJI_0451 tot en met DJI_0467 (nog op de SD-kaart).
  - **De foto's zijn nu 4000 × 3000 (4:3).** Dat is goed.
  - **In alle 17 foto's kijkt de camera vooruit naar de horizon** in plaats van naar beneden. In de foto zelf staat de gimbal op 0°. Het doorzichtige kapje zat nog om de camera, dus de camera kon niet draaien. Toch nam DJI de opdracht "camera naar beneden" aan, steeg de drone op en maakte hij foto's.
  - Nu wacht de app vóór het opstijgen tot de gimbal zelf meldt dat hij op −90° staat (hooguit 3 seconden). Lukt dat niet, of meldt de gimbal dat hij overbelast is, dan stijgt de drone niet op en zegt de app: *Zit het doorzichtige kapje nog om de camera?* Twee nieuwe nep-drone-tests.
  - Het kapje staat nu ook in de controlelijst vóór een echte vlucht.
  - In het logboek schreef de app meteen *Camera recht naar beneden*, en daarna nooit *De camera kijkt even niet recht naar beneden*. De gimbal meldde dus niets, of ongeveer −90°. Meldde hij niets, dan houdt de nieuwe controle de drone nu op de grond. Meldde hij −90° terwijl de camera vastzat, dan helpt alleen de controlelijst. Daarom zet het logboek nu achter *Camera recht naar beneden* de hoek die de gimbal meldt.
  - Om 8:42:15 was de verbinding met de drone ongeveer 5 seconden weg. De app stopte met sturen, zoals bedoeld. Na **Hervatten** ging de route verder vanaf foto 2, en alle 17 foto's zijn bevestigd.
  - Het automatische landen hield twee keer op: om 8:45:09 en 8:45:34 stond de drone weer in vluchtstand *GPS*. De derde keer landde hij wel, na een tik op **Landen**. Nog uitzoeken: stopte de drone vanzelf, of werd een stick of de pauzeknop aangeraakt?
  - Uit de foto's: op de banen heen kantelde de drone 12 à 13°, en terug maar −2°. Er stond dus waarschijnlijk flinke wind langs de banen.
- **Nog nooit getest:** een lange echte vlucht; een echt sensorkastje; jouw eigen indruk van alle schermen.

**Let op:** met een gratis Apple ID werkt de app een week. Daarna zet je hem opnieuw op de iPhone (▶ in Xcode, of vraag het Claude).

## A. Zonder drone (binnen, ongeveer 10 minuten)

- [x] **A1** De app opent met onderaan vier tabbladen: *Drone*, *Route*, *Veldkaart* en *Vluchten*.
  - Op het beginscherm van de iPhone staat het nieuwe icoon: een groen veld met witte vliegbanen en een drone.
- [x] **A2** *Route* → **Voorbeeldroute laden**. Je hoort dit te zien:
  - vier tegels: *Afstand* 2,52 km (20 routepunten), *Vliegtijd* 12:04 min, *Foto's* 180 en *Hoogte* 30 m;
  - een groene kaart *Route is in orde*;
  - onderaan de groene knop **Vliegen in de simulator…**
- [x] **A3** *Route* → tik op het kaartje bovenaan (**Toon op de kaart**). Je hoort dit te zien:
  - de luchtfoto met 10 gele banen, oranje stippellijnen en witte stipjes;
  - een blauw huisje en een groene vlag.
  - Wissel met *Kaart* rechtsboven naar Apple en terug.
- [ ] **A4** Een eigen route uit de planner:
  1. Klik in de planner op *Download JSON*.
  2. Zet het bestand op de iPhone, met AirDrop of via iCloud Drive.
  3. Open het: *Route* → **Routebestand openen…**
  4. Probeer het ook via de Bestanden-app: houd het bestand ingedrukt → *Deel* → *Veldvlucht*.
- [ ] **A5** Open een willekeurig ander JSON-bestand. Er hoort een duidelijke rode melding te komen, en geen crash.
- [x] **A6** *Veldkaart*. Je hoort dit te zien:
  - de weerbalk met het beste vliegmoment;
  - 5 stroken (blauw, blauw, geel, geel, rood), 3 paarse markeringen en 3 turquoise druppels.
- [x] **A7** Tik op een strook (*Waarop gebaseerd*), een druppel (grafiek) en een paarse markering (reden).
- [x] **A8** De app vraagt om je locatie. Kies *Bij gebruik van app*: op de kaart hoort een blauwe stip te staan waar je bent.
- [ ] **A9** *Veldkaart* → tik op **Voorbeeldgegevens**, onder de naam van het veld:
  - kies **Eigen bestand laden…** en neem een bestand uit `docs/voorbeelden`. Onder de naam staat dan *Eigen gegevens: …*;
  - kies daarna **Voorbeeldgegevens gebruiken**.
- [x] **A10** *Vluchten* toont nog *Nog geen vluchten*.
- [ ] **A11** Buiten in de zon: is de veldkaart in één oogopslag te lezen? (stap 7, punt 3) En de tegels op het tabblad *Drone*?
- [x] **A12** Zet de iPhone op donker (*Instellingen → Weergave en helderheid → Donker*). Is alles nog goed te lezen? Zet hem daarna terug zoals je wilt.

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

- [x] **C1** **Simulator starten**:
  - de badge wordt groen (*SIMULATOR*);
  - het rode vliegtuigje springt naar het startpunt van de route.

  Lukt dit niet, stuur dan het logboek: of de simulator van de SDK op de Mavic Mini werkt, is nog onbekend.
- [x] **C2** **Route starten** → vink de drie punten af → **Starten**. Onderin gaan de fases voorbij: *Voorbereiden → Opstijgen → Klimmen → Richtingtest → Naar het begin → Route vliegen*.
- [x] **C3** **Vraag 1, de richting:** wat staat er na de richtingtest in het logboek? (Bijvoorbeeld *pitch = oost, roll = noord*.) Schrijf het hier op: *pitch = oost, roll = noord (zoals DJI beschrijft)*, 2 november 2026
- [x] **C4** **Vraag 2, de foto's:** (5 van 5 op 30 m met *Vliegtest #1*; kijk bij C11 nog eens met 180 foto's)
  - vliegt het vliegtuigje over de gele lijnen?
  - worden de stippen **groen**, zonder rode?
  - staat de hoogte rond 30 m en de snelheid rond 4 m/s?
- [x] **C5** **Vraag 3, hervatten:** druk midden in een baan op **Pauze** en wacht 10 seconden: hangt hij stil? Druk dan op **Hervatten**: gaat hij terug naar waar hij stopte en verder, zonder dubbele foto's?
- [x] **C6** Druk op **Overnemen**. Je hoort te zien: *Overgenomen: jij vliegt*. Daarna hoort **Hervatten** weer te werken.
- [x] **C7** Beweeg tijdens de route **kort een stick**. Je hoort te zien: *Je bewoog een stick: de app stuurt niet meer*. (Nodig om echt vliegen vrij te geven.)
  - Houd daarna een stick vast en druk op **Hervatten**. In het logboek hoort te staan: *Laat eerst de sticks los*.
- [x] **C8** (6 november 2026, 9:56: de drone keerde zelf terug en de app stuurde niet meer) Druk op de **pauze/terugkeerknop van de afstandsbediening**. Wat doet de drone, en wat zegt de app? Je verwacht *De drone keert zelf terug*, zonder dat de app ertegenin stuurt.
- [x] **C9** (6 november 2026: de app nam over en ging niet vanzelf verder; de simulator stopte bij het lostrekken) Trek tijdens de route **de kabel uit de iPhone** en steek hem na 10 seconden terug. Je verwacht:
  - *Overgenomen* (of *De drone keert zelf terug*);
  - de app gaat nooit vanzelf verder.
- [x] **C10** Druk op **Naar huis**: de drone keert terug en landt (in de simulator).
  - Druk tijdens het terugkeren op **Overnemen**. Je hoort *Naar huis is afgebroken; jij vliegt* te zien, en de drone hangt stil.
  - Druk opnieuw op **Naar huis** en, als hij aan het **landen** is, nog eens op **Overnemen**. Je hoort *Landen is afgebroken; jij vliegt* te zien. Lukt het niet, dan hoort er *… afbreken lukt niet* te staan, en **niet** *jij vliegt*.
  - Hangt de drone net boven de grond stil? Dan hoort er te staan: *De drone hangt net boven de grond en wacht* en een groene knop **Landen**. Tik erop: landt hij? Lukt het niet, druk dan op **Overnemen** en houd de linkerstick omlaag tot de motoren stoppen.
- [x] **C11** (6 november 2026: 180 van 180, niets gemist) Vlieg één route helemaal af, tot *Klaar* met 180 van 180 foto's. (Nodig om echt vliegen vrij te geven.) Een korte route van 5 foto's lukte al op 2 november en telt voor de app al mee; doe toch de hele voorbeeldroute, ongeveer 12 minuten, **met een volle accu** (op 5 november was de accu na 91 foto's op).
- [x] **C12** **Verder met een nieuwe accu:** (2 november steeg hij twee keer niet op; op 5 november, na drone en simulator opnieuw aan, lukte het wel)
  1. Start de route en druk halverwege op **Naar huis**.
  2. Sluit het vluchtscherm en open het opnieuw.
  3. Zet **Verder vanaf foto …** aan en start: begint hij bij die foto?
- [x] **C13** (gemeld door jou, 6 november) *Vluchten*:
  - de simulatorvluchten staan erin, met groene stippen op de kaart;
  - **Fotolog en logboek delen** werkt met AirDrop naar de Mac;
  - in de Bestanden-app staan de vluchten onder *Op mijn iPhone → Veldvlucht → Vluchten*.
- [x] **C14** (gemeld door jou, 6 november; de nummers in het fotolog lopen door zonder gaten) Op de SD-kaart staan de nieuwe foto's, en de bestandsnamen kloppen met het fotolog.
- [x] **C15** (gemeld door jou, 6 november) Druk op **Simulator stoppen** en zet de drone **uit en weer aan**.
- [x] **C16** (6 november 2026, 9:58: gelukt; een scheve foto slaat de app nu over) **Camera recht naar beneden** (nieuw sinds 6 november). Start een korte route in de simulator, bijvoorbeeld *Vliegtest #2*:
  - Kijk bij het starten naar de drone: draait de camera **recht naar beneden** voordat de motoren starten? In het logboek hoort *Camera recht naar beneden.* te staan.
  - Draai tijdens de route even aan het **wieltje linksboven** op de afstandsbediening, zodat de camera kantelt. Je hoort te zien: *De camera kijkt even niet recht naar beneden (…°). De app wacht met de foto en draait hem terug.* De camera gaat weer naar beneden, en een foto die op dat moment aan de beurt was, telt als *gemist*.

## D. Eerste echte vluchten (stap 5), alleen als blok C helemaal goed ging

**Voorwaarden:**
- een open veld zonder mensen of dieren, goed weer en weinig wind;
- het doorzichtige **kapje is van de camera af** (anders kan de camera niet naar beneden draaien);
- je bent geregistreerd als exploitant en mag daar vliegen (geen no-fly-zone, maximaal 120 m);
- je bent zelf de piloot en ziet de drone de hele vlucht;
- de **propellers zitten erop en goed vast**.

- [x] **D1** (6 november 2026: *Echte vlucht test #1*, 4 foto's) Maak in de planner een **korte route**: 2 à 3 banen, korter dan 800 m, met het startpunt waar je staat. Zet hem op de iPhone.
- [x] **D2** (6 november 2026) Open het vluchtscherm. De keuze **Echt vliegen** hoort te verschijnen (vrijgegeven door C7 en C11). Lees de oranje punten en los ze op:
  - minstens 10 satellieten en GPS-signaal 4;
  - het thuispunt is gezet;
  - de accu is minstens 50 %;
  - de drone geeft geen windwaarschuwing;
  - de drone staat binnen 30 m van het startpunt.
- [x] **D3** (6 november 2026, tweede vlucht: Pauze, Hervatten, Overnemen met de knop en met een stick) **Echt vliegen** → vink de controlelijst af → **Alles gecontroleerd: opstijgen**. **Houd de afstandsbediening vast.** Na de richtingtest, op hoogte:
  - probeer **Pauze** en **Hervatten**;
  - probeer **Overnemen** met een stick.
- [x] **D4** (6 november 2026: 4 van 4 foto's op hun plek, en zelf geland na *naar huis*; de camera bleef recht naar beneden) Volgt de drone de banen? Maakt hij de foto's? Landt hij weer bij het startpunt?
  - Even *De camera kijkt even niet recht naar beneden* bij afremmen of optrekken is normaal (6 november: −80° tot −83°, een seconde lang). Worden er daardoor foto's **gemist**, meld het dan: dan staat de grens van 5° te krap.
- [x] **D5** (6 november 2026: GPS en scherpte goed; 16:9 en een scheve camera bij optrekken zijn verbeterd, zie D8) Na de vlucht (stap 5, punt 2):
  1. Zet de foto's van de SD-kaart op de Mac, samen met het fotolog (*Vluchten* → *Delen*).
  2. Controleer: zijn alle geplande foto's er? Liggen ze op de goede plek? Zijn ze scherp genoeg om de planten te beoordelen? Kijkt de camera recht naar beneden (alleen grond, geen horizon)? Staat er GPS in?
- [x] **D6** (6 november 2026: de drone ging zelf naar huis, en de app stuurde niet meer) Op veilige hoogte: wat doet één druk op de **pauzeknop** van de afstandsbediening? Volgens de handleiding remt de drone af. (Hoofdstuk 6.5 van het DJI-document.)
- [x] **D7** (3 van 3 op 6 november 2026; de grens van 800 m is nu weg) Na 3 geslaagde echte vluchten vervalt de grens van 800 m. Ga daarna stap voor stap groter, tot een heel veld.
- [ ] **D8** (9 november 2026: 4:3 klopt, maar het kapje zat nog om de camera, dus de hoek en het optrekken nog een keer) Vlieg nog eens dezelfde korte route, op een plek zonder mensen onder de route. Zet daarna de nieuwe foto's op de Mac (zoals bij D5) en laat Claude ze nakijken:
  - zijn ze nu 4000 × 3000 (4:3)?
  - staat de camera in elke foto binnen 2° van recht naar beneden? (Dat staat in de foto zelf, Claude leest het uit.)
  - de drone trekt nu rustiger op: na de bocht duurt het ongeveer 4 seconden voor hij op 4 m/s vliegt.

## E. Veld tekenen, sensoren, weer en advies (nieuw, 26 oktober 2026)

Wat al getest is: de berekening van de route (gelijk aan de planner), het weer, het wateradvies en het ontvangen van metingen. Dat laatste is getest met nep-metingen vanaf de Mac. Een echt kastje en echte velden nog niet.

- [ ] **E1** Ga naar een veld en open *Route* → **Veld tekenen**. Je hoort dit te zien:
  - de kaart springt naar je eigen plek (blauwe of groene stip);
  - na 3 aangetikte hoeken verschijnen de gele vliegbanen en de witte fotostipjes;
  - onderin staan afstand, vliegtijd, foto's en de grootte van het veld.
- [ ] **E2** Sleep een hoek (vasthouden) en het huisje (startpunt). Haal een hoek weg (aantikken → *Verwijderen*). Probeer de knop met de pijl terug.
- [ ] **E3** *Bewaren* → geef een naam. Het veld staat onder *Mijn velden*; tik erop. Klopt de route met je veld?
- [ ] **E4** Vlieg dit veld in de simulator, net als in blok C (C2 t/m C11).
- [ ] **E5** *⋯* → **Route delen** → AirDrop naar de Mac. Open het bestand in de planner (*JSON laden*): staat dezelfde route er?
- [ ] **E6** *Veldkaart* → tik op de regel onder de naam → kies je veld. Je hoort dit te zien:
  - je veld in grijze stroken (*geen advies*: er zijn nog geen sensoren);
  - het weer van vandaag en de komende dagen, met het beste vliegmoment.
- [ ] **E7** Zet in hetzelfde menu **Melding bij goed vliegweer** aan en sta meldingen toe. Komt er een melding, een uur voor het volgende goede moment?
- [ ] **E8** **Sensoren plaatsen en ijken…**: kies 1 sensor en sleep hem naar de plek waar hij komt. Bewaar. Noteer de naam (bijvoorbeeld `mijn-veld-s1`): ____________________
- [ ] **E9** Bouw het kastje op tafel volgens [sensor/README.md](../sensor/README.md), met die naam. Zet de hotspot aan (met *Maximaliseer compatibiliteit*) en houd Veldvlucht open. Je hoort dit te zien:
  - vraagt de iPhone iets over het **lokale netwerk**, kies dan *Sta toe*;
  - in het sensorscherm *Sensor s1 (…): … meting(en) ontvangen*;
  - op de veldkaart een turquoise druppel met de ruwe waarde.
- [ ] **E10** IJk de sensor met droge en natte grond (*Laatste = droog*, *Laatste = nat*). Staat er daarna een % vocht?
- [ ] **E11** Steek de sensor in de grond van een strook. Na de volgende meting krijgt die strook een kleur. Tik erop: klopt de uitleg (sensor, vocht, regen, regel)?

## F. Het centrale systeem in de cloud (nieuw, 27 oktober 2026)

Wat al getest is: alles op de Mac, zonder echt project (zie boven). Hoe je het installeert en gebruikt, staat in [centraal/README.md](../centraal/README.md).

- [x] **F1** Maak een gratis project op <https://supabase.com> (naam `veldvlucht`, regio in Europa). Het databasewachtwoord bewaar je zelf; niemand heeft het nodig.
- [x] **F2** Draai in de Terminal, in de projectmap:
  ```bash
  bash centraal/installeer.sh
  ```
  Je hoort aan het eind *Klaar* te zien, met:
  - *Rekenkern:* `{"berekend":0,"problemen":[]}`;
  - *Sensorontvangst:* een melding met *Onbekende sleutel*.

  Laat het Claude weten: die zet de nieuwe app op je iPhone.
- [x] **F3** *Route* → het poppetje linksboven → vul je e-mailadres en een wachtwoord in → **Account maken**.
  - Je krijgt een e-mail van Supabase. Klik op de link. (De pagina die opent, mag een foutmelding geven.)
  - Log in. Je hoort een groene kaart *Ingelogd* te zien, met je e-mailadres.
- [x] **F4** **Nu synchroniseren**. Bij *Laatst gesynchroniseerd* staat de tijd van nu. Kijk in het dashboard van Supabase bij *Table Editor* → `velden`: staan je velden erin?
- [x] **F5** *Veldkaart* → je veld → **Sensoren plaatsen en ijken…** → **Bewaren**. Bij elke sensor staat nu een **sleutel**, met een kopieerknopje.
- [x] **F6** **Een nep-kastje naar de cloud**, vanaf de Mac. Vul de drie waarden in (*Route* → het poppetje, en de sleutel uit F5):
  ```bash
  python3 sensor/nep-sensorkastje.py --cloud JOUW_PROJECT --cloud-sleutel JOUW_CLOUD_SLEUTEL --sensor-sleutel JOUW_SENSOR_SLEUTEL --sensor mijn-veld-s1
  ```
  - Het programma hoort te melden dat de metingen zijn ontvangen.
  - Synchroniseer de app: staat de turquoise druppel er, met de metingen?
  - Elke keer dat je dit draait, komen er nieuwe nep-metingen bij. Dat hoort zo: het nep-kastje doet alsof het opnieuw is aangezet.
- [ ] **F7** Hetzelfde met het **echte kastje** (zie [sensor/README.md](../sensor/README.md)): zet `CLOUD_PROJECT`, `CLOUD_SLEUTEL` en `SENSOR_SLEUTEL` in `Instellingen.h` en zet het programma opnieuw op het bordje.
  - Zet de hotspot aan, maar laat de app **dicht**.
  - In de Serial Monitor hoort te staan: *Gelukt. De cloud zegt: …*
  - Open daarna de app: zijn de metingen er?
- [x] **F8** IJk de sensor (E10) en kies in het menu van de veldkaart **Advies nu laten berekenen**. Tik op de strook met de sensor. Onderaan hoort te staan: *Berekend door het centrale systeem in de cloud*.
- [x] **F9** Zet de iPhone in **vliegtuigmodus** en open de veldkaart. Het advies hoort er nog te zijn. Haal vliegtuigmodus weer weg.
- [ ] **F10** **Delen:**
  1. *Veldkaart* → menu → **Delen met anderen…** → vul een tweede e-mailadres in. Dat moet al een account hebben: maak het eerst, net als bij F3.
  2. Log uit, en log in met dat tweede account.
  3. Je hoort het veld te zien bij *Gedeeld met mij*, met sensoren en advies. Er is geen knop om iets te veranderen.
  4. Log weer in met je eigen account. Haal het tweede adres weg bij *Delen*.
- [ ] **F11** **Elk uur:** kijk de volgende dag in het dashboard bij *Table Editor* → `resultaten`. De tijd bij `berekend` hoort van het laatste uur te zijn (7 over), ook als de app dicht was.
- [ ] **F12** **Foto-analyse** na een vlucht in de simulator (C11) of een echte vlucht (D5):
  1. Zet de foto's en het fotolog in een eigen map op de Mac.
  2. Draai de analyse:
     ```bash
     swift run --package-path ios/VeldvluchtKern foto-analyse ~/Pictures/vlucht-1
     ```
  3. Je hoort per foto het aantal planten te zien. In de simulator fotografeert de drone geen veld, dus daar zijn het er 0 of een paar.
  4. Bij een echte vlucht boven een veld: probeer ook `--upload`. Synchroniseer de app: staan er paarse markeringen? Kloppen ze met wat je in het veld ziet?

## Wat je naar Claude stuurt

- De logboeken van C2 t/m C12, en van elke echte vlucht.
- Het antwoord bij **C3** (richting).
- Bij D: hoeveel foto's gepland en gemaakt zijn, en of ze scherp zijn en GPS hebben.
- Bij E: de naam bij E8, wat het kastje in de Serial Monitor zegt, en een schermafbeelding van het sensorscherm.
- Bij F: wat het installatiescript aan het eind zegt (geen sleutels of wachtwoorden), en bij F12 wat de analyse per foto zegt.
- Alles wat er vreemd uitziet, met een schermafbeelding.
