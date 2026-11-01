#!/bin/bash
# Installs the central system of Veldvlucht in your Supabase project (centraal/README.md):
# the database, the hourly job and the edge function `centraal`, and puts the project's
# address and publishable key in ios/Config/Lokaal.xcconfig for the app.
#
# Run it in Terminal, from the repository folder:
#   bash centraal/installeer.sh
# It can be run again; nothing is lost. Your database password is not needed.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

SUPABASE=.tools/supabase/supabase
LOKAAL=ios/Config/Lokaal.xcconfig

stap() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fout() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ -x "$SUPABASE" ] || fout "Het hulpprogramma van Supabase ontbreekt ($SUPABASE). Zie centraal/README.md, 'Opnieuw installeren'."
[ -f "$LOKAAL" ] || fout "$LOKAAL ontbreekt. Zie ios/README.md, 'Eenmalig: je App Key invullen'."

stap "1. Inloggen bij Supabase"
if ! "$SUPABASE" projects list -o json >/dev/null 2>&1; then
  echo "Er opent een browser. Log in bij Supabase en geef toestemming; kom daarna terug naar dit venster."
  "$SUPABASE" login
fi
echo "Ingelogd."

stap "2. Je project zoeken"
PROJECTEN=$("$SUPABASE" projects list -o json 2>/dev/null)
REF=$(printf '%s' "$PROJECTEN" | python3 -c '
import json, sys
try:
    projects = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if isinstance(projects, dict):
    projects = projects.get("projects", [])
named = [p for p in projects if str(p.get("name", "")).lower() == "veldvlucht"]
pick = named or (projects if len(projects) == 1 else [])
if pick:
    print(pick[0].get("id") or pick[0].get("ref") or "")
')
if [ -z "$REF" ]; then
  echo "Ik vind geen project met de naam veldvlucht. Dit zijn je projecten:"
  "$SUPABASE" projects list
  read -r -p "Typ de REFERENCE ID van het project (de letters voor .supabase.co): " REF
fi
[[ "$REF" =~ ^[a-z0-9]{10,40}$ ]] || fout "'$REF' is geen geldige project-ref."
echo "Project: $REF (https://$REF.supabase.co)"

stap "3. De database klaarzetten"
"$SUPABASE" db query --linked --project-ref "$REF" --workdir "$ROOT/centraal" -f "$ROOT/centraal/supabase/migrations/20261027120000_veldvlucht.sql" >/dev/null
"$SUPABASE" db query --linked --project-ref "$REF" --workdir "$ROOT/centraal" -f "$ROOT/centraal/supabase/migrations/20261027120100_elk_uur.sql" >/dev/null
"$SUPABASE" db query --linked --project-ref "$REF" --workdir "$ROOT/centraal" \
  "insert into public.instellingen (naam, waarde) values ('project_url', 'https://$REF.supabase.co') on conflict (naam) do update set waarde = excluded.waarde" >/dev/null
echo "Tabellen, regels, functies en de taak van elk uur staan klaar."

stap "4. De rekenkern in de cloud zetten"
"$SUPABASE" functions deploy centraal --project-ref "$REF" --no-verify-jwt --use-api --workdir "$ROOT/centraal"

stap "5. De app instellen"
SLEUTELS=$("$SUPABASE" projects api-keys --project-ref "$REF" -o json 2>/dev/null)
KEY=$(printf '%s' "$SLEUTELS" | python3 -c '
import json, sys
try:
    keys = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
def value(k):
    return k.get("api_key") or k.get("apiKey") or k.get("key") or ""
publishable = [k for k in keys if str(k.get("type", "")).lower() == "publishable" or value(k).startswith("sb_publishable_")]
anon = [k for k in keys if str(k.get("name", "")).lower() == "anon"]
pick = publishable or anon
if pick:
    print(value(pick[0]))
')
[ -n "$KEY" ] || fout "Ik vind de publishable key niet. Kopieer hem uit het dashboard (Project Settings → API Keys) en zet hem in $LOKAAL bij SUPABASE_KEY."
# Earlier lines out, the new ones in; the DJI key and the team stay as they are.
grep -v -E '^SUPABASE_(PROJECT|KEY)[[:space:]]*=' "$LOKAAL" > "$LOKAAL.nieuw" || true
printf '\n// Het centrale systeem in Supabase (centraal/installeer.sh)\nSUPABASE_PROJECT = %s\nSUPABASE_KEY = %s\n' "$REF" "$KEY" >> "$LOKAAL.nieuw"
mv "$LOKAAL.nieuw" "$LOKAAL"
echo "In $LOKAAL staan nu SUPABASE_PROJECT en SUPABASE_KEY. (Dat bestand komt niet in git.)"

stap "6. Even proberen"
AUTH=()
if [[ "$KEY" == eyJ* ]]; then AUTH=(-H "Authorization: Bearer $KEY"); fi
ANTWOORD=$(curl -s -m 60 -X POST "https://$REF.supabase.co/functions/v1/centraal" -H 'Content-Type: application/json' -d '{}' || true)
echo "Rekenkern: $ANTWOORD"
ANTWOORD=$(curl -s -m 30 -X POST "https://$REF.supabase.co/rest/v1/rpc/sensor_upload" -H "apikey: $KEY" ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' -d '{"p_sleutel":"proef","p_upload":{}}' || true)
echo "Sensorontvangst (hoort 'Onbekende sleutel' te zeggen): $ANTWOORD"

stap "Klaar"
cat <<EOF
Het centrale systeem draait in je project $REF.
Wat nu:
  1. Zet de app opnieuw op je iPhone (▶ in Xcode, of vraag het Claude).
  2. Open in de app: Route → het poppetje linksboven → Account maken.
  3. Bevestig je e-mailadres met de link in de e-mail van Supabase, en log in.
EOF
