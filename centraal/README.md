# Het centrale systeem van Veldvlucht

Het centrale systeem uit [ARCHITECTUUR.md](../docs/ARCHITECTUUR.md), hoofdstuk 4. Het draait gratis in **Supabase**, een clouddienst met een database, inloggen en kleine programma's in de cloud.

**Wat het doet:**

- **Bewaren:** je velden, de sensoren met hun sleutels, alle sensormetingen, het weer, het advies en de fotologs van je vluchten.
- **Sensormetingen ontvangen:** een sensorkastje stuurt via de hotspot van je iPhone rechtstreeks naar de cloud, met de geheime sleutel van zijn sensor. De app hoeft dan niet open te zijn.
- **Weer en advies, elk uur:** om 7 over elk uur haalt de cloud het weer op bij Open-Meteo en rekent het wateradvies per strook uit. Na nieuwe metingen of een veranderd veld gebeurt dat meteen. Het zijn dezelfde regels als in de app (`ios/VeldvluchtKern/…/WaterAdvisor.swift`); de tests controleren dat ze hetzelfde uitkomen.
- **Delen:** de eigenaar van een veld kan anderen met een Veldvlucht-account laten meekijken. Zij zien het veld, de sensoren, het weer en het advies, maar kunnen niets veranderen.
- **Foto-analyse:** die draait op je Mac, want de foto's zijn te groot voor de gratis cloud (zie "De foto-analyse op je Mac"). De gevonden planten komen in de cloud en zo op de veldkaart.

**Wat het nog niet doet:** een getrainde AI. De foto-analyse en het advies werken met eenvoudige regels die je kunt controleren (hoofdstuk 7 van ARCHITECTUUR.md).

## Wat er in deze map staat

| Bestand | Wat het is |
|---|---|
| `installeer.sh` | **Zet alles in je Supabase-project.** Je kunt het vaker draaien; er gaat niets verloren. |
| `supabase/migrations/…_veldvlucht.sql` | De database: tabellen, wie wat mag zien, delen, en het ontvangen van sensormetingen. |
| `supabase/migrations/…_elk_uur.sql` | De taak van elk uur (pg_cron), en meteen opnieuw rekenen na nieuwe metingen. |
| `supabase/functions/centraal/index.ts` | Het programma in de cloud (een *edge function*). |
| `supabase/functions/_shared/rekenkern.ts` | De berekeningen: stroken, weer, vliegmomenten en wateradvies. |
| `supabase/functions/_shared/werk.ts` | Wat het programma per veld doet: weer ophalen, advies uitrekenen, opslaan. |
| `tests/` | De tests (zie "Testen"). |

## Installeren

**Eenmalig: een project maken** (dat doe je zelf, met je eigen account):

1. Ga naar <https://supabase.com> en klik op **Start your project**. Log in met GitHub of je e-mailadres.
2. Kies het gratis plan (**Free**). Betaalgegevens zijn niet nodig.
3. **New project**:
   - **Name:** `veldvlucht`;
   - **Database Password:** verzin een sterk wachtwoord en bewaar het in je wachtwoordbeheer. Je hebt het voor de installatie niet nodig;
   - **Region:** iets in Europa, bijvoorbeeld *Central EU (Frankfurt)*;
   - **de andere opties:** laat die staan zoals ze staan. Zet de **Data API** niet uit, want de app en de kastjes praten daarmee. *Automatically expose new tables* mag aan of uit: het installatiescript regelt de rechten zelf.
4. Wacht tot het project klaar is.

**Het centrale systeem installeren:**

1. Open de Terminal en ga naar de projectmap:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner
   ```
2. Start het installatiescript:
   ```bash
   bash centraal/installeer.sh
   ```
3. Er opent een browser: **log in bij Supabase en geef toestemming**. Kom daarna terug naar de Terminal.
4. Vraagt het om een databasewachtwoord: **druk gewoon op Enter**.
5. Aan het eind staat *Klaar*, met twee regels "Even proberen":
   - *Rekenkern:* `{"berekend":0,"problemen":[]}` (er zijn nog geen velden);
   - *Sensorontvangst:* een melding met *Onbekende sleutel*. Dat is goed: het was een nep-sleutel.

Het script zet het adres en de publishable key van het project in `ios/Config/Lokaal.xcconfig`. Dat bestand komt niet in git. De publishable key mag in de app staan, net als bij elke app die Supabase gebruikt; geheim is alleen de *secret key*, en die gebruikt de app nergens.

**Daarna in de app:**

1. Zet de app opnieuw op je iPhone (▶ in Xcode, of vraag het Claude).
2. Tabblad **Route** → het poppetje linksboven → **Account maken**, met je e-mailadres en een wachtwoord.
3. Je krijgt een e-mail van Supabase. Klik op de link om je adres te bevestigen. (De pagina die dan opent, mag een foutmelding geven: het bevestigen is toch gelukt.)
4. Log in. De app zet je velden in de cloud en haalt metingen, weer en advies op. Dat gebeurt daarna vanzelf als je de app opent.

## Een sensorkastje rechtstreeks naar de cloud

1. In de app: *Veldkaart* → tik op de regel onder de naam van je veld → **Sensoren plaatsen en ijken…** → **Bewaren**. Bij elke sensor verschijnt dan een **sleutel**.
2. In de app: *Route* → het poppetje → onderaan staan **CLOUD_PROJECT** en **CLOUD_SLEUTEL**.
3. Zet die drie in `Instellingen.h` van het kastje (zie [sensor/README.md](../sensor/README.md)) en zet het programma opnieuw op het bordje.

Het kastje probeert eerst de cloud, en anders de app. Een meting die twee keer aankomt, telt maar één keer.

## De foto-analyse op je Mac

Na een vlucht:

1. Zet de foto's van de SD-kaart van de drone in een **eigen map** op je Mac, één map per vlucht.
2. Zet het **fotolog** van die vlucht in dezelfde map: in de app *Vluchten* → de vlucht → **Fotolog en logboek delen** → AirDrop naar de Mac.
3. Ga in de Terminal naar de projectmap:
   ```bash
   cd ~/Documents/GitHub/drone-routeplanner
   ```
4. Start de analyse, met de map met de foto's:
   ```bash
   swift run --package-path ios/VeldvluchtKern foto-analyse ~/Pictures/vlucht-1
   ```
   Je ziet per foto hoeveel planten er zijn en hoeveel er opvallen. Het programma schrijft `aandacht.geojson` in de map.
5. Tevreden? Zet de plekken in het centrale systeem:
   ```bash
   swift run --package-path ios/VeldvluchtKern foto-analyse ~/Pictures/vlucht-1 --upload
   ```
   Log in met je Veldvlucht-account (hetzelfde als in de app). Daarna staan de plekken als paarse markeringen op de veldkaart, met de reden en de naam van de foto.

**Hoe het werkt (niveau 1 uit ARCHITECTUUR.md, zonder getrainde AI):**

- Per foto zoekt het de groene vlekken: de planten. Kale grond is bruin of grijs.
- Per plant meet het hoe groen en hoe groot die is.
- Planten die **veel minder groen** of **veel kleiner** zijn dan de andere planten op dezelfde foto, krijgen de markering *aandacht nodig*.
- Uit de plek van de drone, de hoogte en de vliegrichting (in het fotolog) rekent het uit waar die plant op de grond staat. Zie je dezelfde plant op twee foto's, dan telt hij één keer.
- **Grenzen:**
  - het werkt alleen met foto's recht naar beneden;
  - onkruid en schaduw kunnen meetellen;
  - watertekort dat je nog niet ziet, ziet de analyse ook niet.

  Controleer de markeringen dus in het veld.

## Testen

Op de Mac, zonder het echte project:

```bash
cd ~/Documents/GitHub/drone-routeplanner
```
```bash
PATH="$PWD/.tools/node/bin:$PATH" npm test
```

- `tests/database.test.ts` draait de database in **PGlite**, een echte Postgres in Node. De test controleert:
  - dat je alleen je eigen en gedeelde velden ziet;
  - het delen;
  - dat de sleutels van de kastjes alleen voor de eigenaar zijn;
  - het ontvangen van metingen zonder dubbele;
  - dat niemand zonder login iets kan lezen;
  - dat de rechten hetzelfde zijn in beide soorten Supabase-projecten: nieuwe projecten geven tabellen sinds mei 2026 niet meer vanzelf rechten, oudere wel.
- `tests/rekenkern.test.ts` rekent dezelfde gevallen door als de tests van de app (`CentralTests.swift`). Die moeten precies hetzelfde advies geven, met dezelfde uitleg.
- `tests/werk.test.ts` draait het programma van elk uur tegen een nep-database.

## Kosten en grenzen

Gratis plan van Supabase (stand oktober 2026, controleer op <https://supabase.com/pricing>):

- 500 MB database en 1 GB bestanden. Een sensor die elk uur meet, gebruikt een paar MB per jaar. De foto's zelf gaan niet naar de cloud.
- **Een project zonder activiteit wordt na 7 dagen gepauzeerd.** Zolang een kastje metingen stuurt of je de app gebruikt, is er activiteit. Is het toch gepauzeerd, zet het dan in het dashboard weer aan (*Restore project*). Er gaat niets verloren.
- Open-Meteo is gratis voor niet-commercieel gebruik, met bronvermelding.

## Opnieuw installeren of op een andere Mac

De hulpprogramma's staan in `.tools/`, niet in git. Op een andere Mac heb je nodig:
- de Supabase CLI van <https://github.com/supabase/cli/releases>, uitgepakt in `.tools/supabase/`;
- voor de tests Node.js 24 van <https://nodejs.org>, in `.tools/node/`.

Controleer bij elke download de controlesom (de SHA-256 in het bestand met checksums bij de release). Draai daarna `bash centraal/installeer.sh` opnieuw.
