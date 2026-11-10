# Sensorkastje: bodemvocht meten met een ESP32

Het programma voor één sensorkastje uit [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md), hoofdstuk 2: een ESP32-bordje met de bodemvochtsensor van school. Het kastje meet en stuurt de metingen via de **hotspot van je iPhone** naar het **centrale systeem in de cloud** ([centraal/README.md](../centraal/README.md)), of naar de Veldvlucht-app.

**Zo werkt het:**

0. **Koppelen, één keer:** zet je het kastje aan, dan maakt het 2 minuten lang een eigen wifi-netwerk. Daarmee stuurt de Veldvlucht-app het je hotspot, de naam en sleutel van de sensor en de cloud. Zie "Koppelen met de app".
1. Het kastje slaapt en wordt **elk uur** wakker.
2. Het zet de sensor **heel even aan** (0,2 seconde), meet 10 keer en neemt de middelste waarde. Daarna zet het de sensor weer uit.
3. Het **bewaart** de meting in zijn geheugen.
4. Het probeert 10 seconden lang verbinding te maken met de hotspot van je iPhone.
5. Lukt dat, dan stuurt het **alle bewaarde metingen**:
   - naar het **centrale systeem in de cloud**, als je dat hebt ingesteld (beveiligd met https). De app hoeft dan niet open te zijn;
   - anders, of als de cloud niet antwoordt, naar de **Veldvlucht-app** op de iPhone.

   Pas als de cloud of de app zegt dat ze zijn opgeslagen, gooit het kastje ze weg.
6. Wifi uit, en weer slapen tot de volgende meting.
7. **Druk je op de knop BOOT**, dan wordt het kastje meteen wakker: het meet en verstuurt direct. Handig in het veld, zodat je niet tot een uur hoeft te wachten.

**Wat het kastje niet doet:**

- Het heeft **geen klok** met de echte tijd. Het stuurt bij elke meting mee hoe lang geleden die was. De app rekent daar de tijd van uit.
- Elke meting krijgt een **volgnummer**. Mist het kastje het antwoord van de app en stuurt het dezelfde metingen nog eens, dan bewaart de app ze niet dubbel.
- Het neemt geen beslissingen. Het meet en verstuurt alleen.

## Wat er in deze map staat

| Bestand | Wat het is | In git? |
|---|---|---|
| `Veldsensor/Veldsensor.ino` | **Het programma voor het kastje.** Dit open je in de Arduino IDE. | Ja |
| `Veldsensor/Instellingen.voorbeeld.h` | Voorbeeld van je instellingen, zonder wachtwoord. | Ja |
| `Veldsensor/Instellingen.h` | **Niet meer nodig** als je koppelt met de app. Alleen voor de testmodus of andere pinnen, of als je toch alles zelf invult. Alleen op deze Mac. | **Nee** (`.gitignore`) |
| `nep-sensorkastje.py` | Doet alsof het een kastje is. Om de app te testen zonder ESP32. | Ja |

## Wat er al gedaan is (26 oktober 2026)

- Het programma **compileert zonder fouten of waarschuwingen** (met alle waarschuwingen aan), voor het bord *ESP32 Dev Module*:
  - met de ESP32-software **3.3.12** van Espressif;
  - grootte: 947.868 bytes (72% van de ruimte op het bordje), werkgeheugen 48.424 bytes (14%).
  - ook gecontroleerd: met TESTMODUS aan en met een batterijpin, en dat een verkeerde pin of een ontbrekende `Instellingen.h` een duidelijke foutmelding geeft.
- Het bewaren en het maken van het bericht voor de app zijn **getest op de Mac**: de volgorde, de leeftijd in seconden, een vol geheugen (200 metingen) en metingen zonder batterij.
- `nep-sensorkastje.py` is getest met een testserver op de Mac, en met de app op je iPhone (via wifi).
- **Erbij gekomen op 27 oktober 2026:**
  - een volgnummer per meting, zodat dubbel verstuurde metingen maar één keer tellen;
  - de knop **BOOT** om meteen te meten en te versturen;
  - **rechtstreeks naar de cloud** (https, met de sleutel van de sensor). Met de cloud ingesteld is het programma 1.110.576 bytes (84%); zonder cloud laat de compiler dat deel weg.
- **Erbij gekomen op 10 november 2026: koppelen met de app.**
  - Het kastje maakt bij het aanzetten 2 minuten lang een eigen wifi-netwerk, *Veldsensor-* met vier tekens. Heeft het nog geen instellingen, dan blijft dat netwerk aan.
  - De app (of een browser op `http://192.168.4.1`) stuurt de instellingen; het kastje controleert ze en bewaart ze in zijn geheugen, ook als de stroom eraf gaat.
  - `Instellingen.h` is niet meer nodig. Wat erin staat, telt nog wel, tot het kastje gekoppeld is.
  - Het programma compileert zonder fouten of waarschuwingen: 1.148.344 bytes (87% van de ruimte), met en zonder `Instellingen.h`.
  - Het bericht dat de app stuurt is getest op de Mac (`SensorPairingTests`).
- **Nog niet getest:** op een echt ESP32-bordje en met de sensor. Ook het koppelen niet.

**Hulpmiddelen voor de controle**, alleen in de map `.tools/` (niet in git). Er is niets in je thuismap gezet en er was geen beheerderswachtwoord nodig.

- **arduino-cli 1.5.1**, het compileerprogramma van Arduino zonder vensters. **Gecontroleerd voor installatie:**
  - gedownload van de officiële GitHub-pagina van Arduino (<https://github.com/arduino/arduino-cli/releases>), uitgebracht op 5 juni 2026;
  - de controlesom (SHA-256) klopt met de lijst die Arduino bij die versie publiceert;
  - het programma is ondertekend door *ARDUINO SA* en door Apple gecontroleerd (*notarized*).
- **ESP32-software 3.3.12** van Espressif, de maker van de ESP32-chip. **Gecontroleerd:**
  - uit de officiële lijst van Espressif (`espressif.github.io`), uitgebracht op 18 september 2026;
  - alle 18 downloads komen van de GitHub-pagina's van Espressif en hebben de juiste controlesom.
- **Ruimte:** samen 7,8 GB. Daarvan is 1,8 GB alleen de downloads (`.tools/arduino/downloads`); die mogen weg.

## Wat je nodig hebt

| Onderdeel | Ongeveer | Let op |
|---|---|---|
| **ESP32-bordje** ("ESP32 DevKit", met een ESP32-WROOM-32) | €5 tot €12 | Een gewone ESP32, **geen** ESP32-S3 of -C3: die hebben andere pinnen. |
| **Bodemvochtsensor** van Bits & Parts (meetvork + printje) | €1,50 | Die van school. |
| **3 jumperdraadjes**, female-female ("Dupont") | €2 tot €4 voor een setje | Van de pinnetjes van het printje naar die van het bordje. |
| **USB-kabel die data doorgeeft** | €4 tot €8 | Je MacBook heeft alleen **USB-C**. Neem een kabel van USB-C naar de aansluiting op het bordje (meestal micro-USB, soms USB-C). Veel goedkope kabels kunnen **alleen opladen**: dan ziet de Mac het bordje niet. |

Later, voor het veld: een powerbank en een waterdicht doosje.

## Aansluiten

**Haal eerst de USB-kabel uit het bordje.** Sluit dan aan:

| Sensorprintje | ESP32-bordje | Waarom |
|---|---|---|
| **VCC** | **GPIO 25** (op het bordje vaak *D25* of *25*) | Het bordje zet de sensor alleen aan tijdens een meting. |
| **GND** | **GND** | De min. |
| **AO** | **GPIO 34** (*D34* of *34*) | De analoge uitgang: de mate van vocht. |
| DO | niets | De aan/uit-uitgang gebruiken we niet. |

- De **meetvork** gaat met de twee draadjes die erbij zitten naar de twee pinnetjes aan de andere kant van het printje. De volgorde maakt niet uit.
- De namen van de pinnen staan soms aan de **onderkant** van het bordje.

**Waarom niet VCC aan 3V3?** Dan staat er altijd stroom op de meetvork. De blote metalen pootjes roesten daardoor snel (zie hoofdstuk 2 van [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md)). Via GPIO 25 staat de sensor maar een paar tienden van een seconde per uur aan. Het printje verbruikt zo weinig stroom dat een GPIO-pin dat aankan.

**Waarom GPIO 34?** De ESP32 heeft twee groepen analoge pinnen. De tweede groep werkt niet als de wifi aan staat. GPIO 32 tot en met 39 horen bij de goede groep.

## Eenmalig: Arduino IDE en de ESP32-software installeren

1. **Download de Arduino IDE** van de officiële website: <https://www.arduino.cc/en/software>. Kies **macOS Intel**. (De nieuwste versie was op 26 oktober 2026 de 2.3.10.)
2. Open het gedownloade `.dmg`-bestand en sleep **Arduino IDE** naar de map *Programma's*.
3. Open de Arduino IDE. Vraagt macOS of je het programma wilt openen, kies **Open**.
4. Kies in de menubalk **Arduino IDE → Settings…** (of **Cmd+,**).
5. Plak bij *Additional boards manager URLs* dit adres en klik op **OK**:
   ```
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```
6. Klik links op het icoon van de **Boards Manager** (het tweede icoon) en zoek op `esp32`.
7. Kies **esp32 by Espressif Systems** en klik op **Install**. Neem **niet** *Arduino ESP32 Boards*.
   - Dit is een grote download (ongeveer 2 GB, uitgepakt rond de 6 GB). Het duurt een tijdje.
8. Kies **Tools → Board → esp32 → ESP32 Dev Module**.

## Koppelen met de app (de makkelijkste manier)

Je hoeft niets in te vullen in de Arduino IDE. Zet het programma op het bordje (zie "Het programma op het bordje zetten") en koppel het daarna zo:

1. **In de app:** *Veldkaart* → tik op de regel onder de naam van je veld → **Sensoren plaatsen en ijken…**. Plaats de sensor en druk op **Bewaren**. Ben je ingelogd, dan krijgt de sensor zijn sleutel voor de cloud.
2. Open **Sensoren plaatsen en ijken…** opnieuw en druk bij je sensor op **Kastje koppelen**.
3. **Zet het kastje aan**, of druk op de knop **EN** van het bordje. Het maakt nu 2 minuten lang een wifi-netwerk: **Veldsensor-** met vier tekens, bijvoorbeeld *Veldsensor-3FA2*.
4. Ga op je iPhone naar **Instellingen → Wifi** en kies dat netwerk. Het wachtwoord is `veldsensor`. Zegt de iPhone *Geen internetverbinding*, dan is dat goed.
5. Ga terug naar Veldvlucht. Vul de **naam van je hotspot** in (de naam van je iPhone) en het **wachtwoord** uit *Instellingen → Persoonlijke hotspot*.
6. Druk op **Koppelen**. Vraagt de iPhone of Veldvlucht apparaten op je lokale netwerk mag zoeken? Kies **Sta toe**, en druk nog een keer op Koppelen.
7. Je ziet *Gekoppeld: het kastje is nu sensor … en meet ruw …*. Ga op je iPhone terug naar je gewone wifi en zet je **Persoonlijke hotspot** aan. Het kastje stuurt zo zijn eerste meting.

- Te laat, en is het netwerk weg? Druk op **EN** en begin bij stap 4.
- Je hotspot-wachtwoord bewaart de app **niet**; alleen het kastje kent het.
- Geen iPhone bij de hand? Ga op een telefoon of laptop naar het netwerk van het kastje en open `http://192.168.4.1` in de browser. Daar staat een formulier met dezelfde vakjes.
- Koppel je het kastje als een **andere sensor**, dan gooit het de metingen weg die het nog niet had verstuurd: die horen bij de oude sensor.

## Of: je instellingen zelf invullen in Instellingen.h

Niet nodig als je koppelt met de app. Wel nodig voor de **testmodus** (zie "Testen op tafel") of als je andere pinnen gebruikt. Wat je hier invult, gebruikt het kastje tot het gekoppeld is.

Je wachtwoord hoef je **aan niemand te geven, ook niet aan Claude**. Je zet het zelf in een bestand dat niet in git komt.

1. Open de Terminal en ga naar de projectmap:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner
   ```
2. Maak je eigen instellingenbestand, als kopie van het voorbeeld:
   ```bash
   cp sensor/Veldsensor/Instellingen.voorbeeld.h sensor/Veldsensor/Instellingen.h
   ```
3. Open het programma in de Arduino IDE:
   ```bash
   open -a "Arduino IDE" sensor/Veldsensor/Veldsensor.ino
   ```
4. Klik bovenaan op het tabblad **Instellingen.h**. Vul **tussen de aanhalingstekens** in:
   - `HOTSPOT_NAAM`: de naam van je iPhone, precies zoals in *Instellingen → Algemeen → Info → Naam*. Let op hoofdletters en spaties.
   - `HOTSPOT_WACHTWOORD`: het wachtwoord uit *Instellingen → Persoonlijke hotspot*.
   - `SENSOR_ID`: de naam van deze sensor. De Veldvlucht-app laat zien wat je hier invult.
   - `DIEPTE_CM`: hoe diep de meetvork in de grond zit.
   - **Voor de cloud** (laat leeg als het kastje alleen naar de app stuurt):
     - `CLOUD_PROJECT` en `CLOUD_SLEUTEL`: in de app onder *Route* → het poppetje linksboven (kopieerknopjes);
     - `SENSOR_SLEUTEL`: de sleutel van deze sensor, in de app onder *Veldkaart* → *Sensoren plaatsen en ijken*. Die is **geheim**: wie hem heeft, kan metingen voor deze sensor sturen.
5. Bewaar met **Cmd+S**.
6. Controleer dat je wachtwoord niet in git komt:
   ```bash
   git status
   ```
   In de lijst mag `sensor/Veldsensor/Instellingen.h` **niet** voorkomen.

**Tip:** staat er in de naam van je iPhone een apostrof (zoals in *Milan’s iPhone*)? Die is lastig goed over te typen. Geef je iPhone dan een simpele naam, zoals *iPhone van Milan*.

## Het programma op het bordje zetten

1. **Verbind het bordje** met de USB-kabel met de Mac.
2. Kies **Tools → Port** en dan de poort met `usbserial` in de naam (of `wchusbserial` of `SLAB_USBtoUART`). **Niet** de poort met *Bluetooth*.
   - Staat er geen van deze poorten? Probeer een **andere kabel**. Installeer geen driver zonder het eerst aan Claude te vragen.
3. Klik op de **pijl naar rechts** (Upload), linksboven.
4. Onderaan verschijnt *Connecting…*. Blijft het daar hangen, **houd dan de knop BOOT** op het bordje ingedrukt tot er percentages verschijnen.
5. Gelukt als er onderaan staat: *Hard resetting via RTS pin…*

## Meekijken met de Serial Monitor

1. Kies **Tools → Serial Monitor**.
2. Zet rechtsboven in het venster de snelheid op **115200 baud**.
3. Druk op de knop **EN** (of **RST**) op het bordje. Het programma begint opnieuw.

Na het aanzetten zie je eerst het koppelen:

```
=== Sensorkastje mijn-veld-s1 ===
Opgestart (stroom aan, resetknop of nieuwe upload).
Koppelen: verbind je iPhone met wifi "Veldsensor-3FA2" (wachtwoord veldsensor) en kies in de app Kastje koppelen.
Het netwerk blijft 2 minuten aan; daarna gaat het kastje meten.
Gekoppeld als sensor mijn-veld-s1, hotspot "iPhone van Milan", met de cloud. Nu: ruw 2875.
Koppelnetwerk uit.
```

Zo ziet een meting eruit als alles goed gaat:

```
=== Sensorkastje mijn-veld-s1 ===
Wakker na het slapen.
Gemeten: ruw 2875 (hoger = droger).
Nog te versturen: 1 meting(en), de oudste van 0 min geleden.
Verbinden met hotspot "iPhone van Milan" ... verbonden na 3.4 s.
Versturen van 1 meting(en) naar http://172.20.10.1:8787/sensormetingen ...
  Gelukt. De app zegt: {"ontvangen":1}
Wifi uit. Slapen tot de volgende meting, over 3586 s.
```

- **Ruw** is de ruwe waarde van de sensor, van 0 tot 4095. Hoger betekent meestal droger.
- Daarna slaapt het kastje een uur. Dan zie je dus een uur lang niets. **Dat is normaal.**

## Testen op tafel met de iPhone

**Voorbereiding:**

1. Maak `Instellingen.h` (zie "Of: je instellingen zelf invullen", stap 1 tot 3) en zet daarin alleen **TESTMODUS** op `true`. Dan meet het kastje elke 10 seconden, zonder te slapen.
2. Zet het programma opnieuw op het bordje (Upload).
3. Op de iPhone: **Instellingen → Persoonlijke hotspot**:
   - zet **Sta anderen toe verbinding te maken** aan;
   - zet **Maximaliseer compatibiliteit** aan. **Belangrijk:** een iPhone 12 of nieuwer (jouw iPhone 13 ook) gebruikt anders 5 GHz. De ESP32 kan alleen 2,4 GHz, en vindt de hotspot dan niet.
4. **Koppel het kastje** met de app (zie "Koppelen met de app"). Dan heeft het precies de naam die de app verwacht.
5. **Open de Veldvlucht-app en laat hem open op het scherm.** De app kan alleen metingen ontvangen als hij open is. Staat hij op de achtergrond of is de iPhone op slot, dan bewaart het kastje de metingen en probeert het later opnieuw.

**De test:**

1. Open de Serial Monitor (115200 baud).
2. Elke 10 seconden hoort er te staan: *Gemeten: ruw …*
3. Daarna: *verbonden na … s* en **Gelukt. De app zegt: {"ontvangen":…}**
4. Kijk in de app (*Sensoren plaatsen en ijken…*) of de metingen van je sensor binnenkomen.
5. Probeer droog en nat:
   - houd de meetvork in de lucht: de waarde komt dicht bij 4095;
   - zet de meetvork in een glas water: de waarde wordt veel lager.
6. **Klaar met testen?** Zet **TESTMODUS** terug op `false` en zet het programma opnieuw op het bordje.

**Werkt het niet?**

| Wat je ziet | Wat je doet |
|---|---|
| *Nog geen hotspot: koppel het kastje* | Koppel het met de app (zie "Koppelen met de app"). |
| *Het kastje antwoordt niet* in de app | Staat je iPhone op de wifi *Veldsensor-…*? Druk op **EN**, kies het netwerk opnieuw en probeer het binnen 2 minuten. |
| *Hotspot niet gevonden* | Staat **Maximaliseer compatibiliteit** aan? Klopt de naam precies? Open op de iPhone het scherm **Persoonlijke hotspot** en laat dat open tot het kastje verbonden is. Ga daarna terug naar Veldvlucht. |
| *Klopt het wachtwoord?* | Koppel het kastje opnieuw met het goede wachtwoord van je hotspot. |
| *App niet bereikbaar* | Is de Veldvlucht-app open, op het scherm? Is de iPhone niet op slot? |
| *De app antwoordde met code 404* en *Onbekende sensor* | Druk in de app bij *Sensoren* op **Bewaren**, en koppel het kastje opnieuw. |
| Ruw is altijd 0 | Zitten VCC aan GPIO 25 en AO aan GPIO 34? |
| Ruw is altijd rond 4095, ook in water | Zitten de draadjes van de meetvork goed vast aan het printje? |
| Geen poort in *Tools → Port* | Een andere USB-kabel proberen: veel kabels laden alleen op. |

## IJken: droog en nat

Het getal *ruw* is geen vochtpercentage. Per grondsoort moet je weten welk getal "droog" is en welk getal "nat". Zo meet je dat:

1. Haal grond van het veld, van de diepte waar de sensor komt. Verdeel het over **twee bakjes**.
2. **Bakje 1, droog:** laat het een paar dagen goed drogen, bijvoorbeeld in de zon of op de verwarming.
3. **Bakje 2, nat:** giet er water bij tot de grond niets meer opneemt. Wacht 10 minuten.
4. Zet **TESTMODUS** op `true` en open de Serial Monitor.
5. Steek de meetvork **helemaal** in bakje 1 en druk de grond goed aan. Wacht een minuut en schrijf een paar waarden op. Dat is je **droge waarde** (`dryRaw`).
6. Spoel en droog de meetvork. Doe hetzelfde in bakje 2. Dat is je **natte waarde** (`wetRaw`).
7. Vul de twee getallen in de app in: *Veldkaart* → tik op de regel onder de naam van je veld → **Sensoren plaatsen en ijken…** → bij je sensor onder **IJken**. Je kunt ook de knoppen **Laatste = droog** en **Laatste = nat** gebruiken, als de app de meting net ontvangen heeft.

Bij de ESP32 lopen de waarden van 0 tot 4095. Jouw getallen zijn dus anders dan in het voorbeeld van hoofdstuk 6.

## Naar het veld

- Zet **TESTMODUS** op `false` (zie hierboven).
- Alleen de meetvork gaat de grond in. Het bordje en het printje blijven **droog** in een doosje.
- **Powerbank:** sommige powerbanks zetten zichzelf uit als er bijna geen stroom gevraagd wordt, zoals als het kastje slaapt. Dan stopt het kastje helemaal. **Probeer het eerst een nacht thuis.**
- **Metingen ophalen:** het kastje probeert te versturen **vlak na een meting**, dus één keer per uur. Wil je niet wachten: zet de hotspot aan, open de app, en **druk op de knop BOOT** van het kastje. Dan meet en verstuurt het meteen.

## Beperkingen

- **Stroom eraf = niet-verstuurde metingen weg.** Het kastje bewaart ze in een geheugen dat het slapen overleeft, maar niet:
  - als de stroom eraf gaat (ook als de powerbank leeg is);
  - als je op de knop **EN** drukt;
  - als je een nieuw programma op het bordje zet.
- **Hoogstens 200 metingen.** Dat is ongeveer 8 dagen bij één meting per uur. Is het geheugen vol, dan gooit het kastje de **oudste** meting weg.
- **De tijd is niet heel precies.** De klok van de ESP32 loopt niet precies gelijk. Hoe langer metingen wachten op versturen, hoe meer de tijd in de app kan afwijken.
- **Eén plek.** Eén sensor meet één plek (zie hoofdstuk 2 van [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md)).

## Batterijspanning meten (optioneel)

Alleen nuttig als het bordje direct op een accu werkt, niet met een powerbank (dan meet je alleen de 5 volt van USB).

1. Zet twee **gelijke weerstanden** (bijvoorbeeld 2 × 100 kΩ) achter elkaar tussen de **plus van de accu** en **GND**.
2. Verbind het punt **tussen** de twee weerstanden met **GPIO 35**.
3. Zet in `Instellingen.h`: `BATTERIJ_PIN` op `35` en `BATTERIJ_DELER` op `2.0`.

Zonder batterijmeting (`BATTERIJ_PIN` is `-1`) stuurt het kastje `null` als batterijspanning.

## De app testen zonder kastje

`nep-sensorkastje.py` stuurt precies hetzelfde bericht als het kastje, met nepmetingen. Python 3 staat al op je Mac.

1. Verbind de **Mac** met de hotspot van je iPhone (het wifi-icoon in de menubalk). De iPhone heeft dan het adres `172.20.10.1`.
2. **Open de Veldvlucht-app** op de iPhone. Plaats daar bij *Sensoren* een sensor met de naam `mijn-veld-s1` (of de naam die je bij `--sensor` gebruikt).
3. Ga in de Terminal naar de projectmap:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner
   ```
4. Stuur 5 nepmetingen:
   ```bash
   python3 sensor/nep-sensorkastje.py 172.20.10.1 --aantal 5 --sensor mijn-veld-s1
   ```
5. Gelukt als onderaan staat: `Antwoord 200: {"ontvangen": 5}`

**Naar de cloud in plaats van de app**, zoals een kastje met de cloud ingesteld:

```bash
python3 sensor/nep-sensorkastje.py --cloud JOUW_PROJECT --cloud-sleutel JOUW_CLOUD_SLEUTEL --sensor-sleutel JOUW_SENSOR_SLEUTEL --sensor mijn-veld-s1
```

Gelukt als onderaan staat: `Antwoord 200: {"nieuw": 5, "ontvangen": 5}`. Daarvoor hoeft de app niet open te zijn.

**Andere mogelijkheden:**

- Zitten de Mac en de iPhone op hetzelfde wifi-netwerk thuis? Gebruik dan het adres van de iPhone uit *Instellingen → Wifi → ⓘ naast het netwerk → IP-adres*.
- Draait de app in de iPhone-simulator op de Mac? Gebruik dan `127.0.0.1`.
- `--geen-batterij` stuurt `null` als batterijspanning, zoals een kastje zonder batterijmeting.
- Alle opties:
  ```bash
  python3 sensor/nep-sensorkastje.py --help
  ```

## Voor Claude: compileren zonder Arduino IDE

Met de arduino-cli in `.tools/`. Er moet wel een `Instellingen.h` zijn.

```bash
.tools/arduino-cli/arduino-cli --config-file .tools/arduino/arduino-cli.yaml compile --fqbn esp32:esp32:esp32 --warnings all --build-path .tools/arduino/build/Veldsensor sensor/Veldsensor
```

Bronnen:

- [Arduino IDE](https://www.arduino.cc/en/software)
- [ESP32-software van Espressif voor Arduino](https://github.com/espressif/arduino-esp32)
- [arduino-cli](https://github.com/arduino/arduino-cli)
- [Productpagina sensor (Bits & Parts)](https://www.bitsandparts.nl/bodemvochtigheidsmeter-analoog-digitaal-p109699)
