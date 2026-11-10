// The central system's regular work (docs/ARCHITECTUUR.md, chapter 4). For every field: fetch
// the weather when the forecast kept is over an hour old, and work out the water advice from
// the sensor measurements, the weather and the attention markers of the photo analysis.
// The edge function `centraal` runs this; the tests run it with a fake database.
import {
  type Attention,
  type FieldRecord,
  type Measurement,
  type Weather,
  centroid,
  openMeteoUrl,
  results,
  weatherFromOpenMeteo,
} from './rekenkern.ts';

/** Where the database is, with the server's own key (it may read every field). */
export interface Env {
  baseUrl: string;
  key: string;
  fetch: typeof fetch;
  now?: () => Date;
}

const WEATHER_MAX_AGE_MS = 3600_000;

interface FieldRow {
  id: string;
  veld_id: string;
  veld: FieldRecord;
}

function database(env: Env) {
  const rest = async (path: string, init: RequestInit = {}): Promise<unknown> => {
    const headers: Record<string, string> = { apikey: env.key, 'Content-Type': 'application/json' };
    // The older keys are JWTs and go in Authorization too; the newer secret keys do not.
    if (env.key.startsWith('eyJ')) headers.Authorization = `Bearer ${env.key}`;
    const response = await env.fetch(`${env.baseUrl}/rest/v1/${path}`, {
      ...init,
      headers: { ...headers, ...((init.headers as Record<string, string>) ?? {}) },
    });
    if (!response.ok) throw new Error(`${path.split('?')[0]}: ${response.status} ${await response.text()}`);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  };
  const upsert = (table: string, row: object) =>
    rest(table, { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(row) });
  return { rest, upsert };
}

async function calculate(env: Env, row: FieldRow, now: Date): Promise<void> {
  const { rest, upsert } = database(env);
  const field = row.veld;
  const kept = ((await rest(`weer?veld=eq.${row.id}&select=verwachting,opgehaald`)) as { verwachting: Weather; opgehaald: string }[])[0];
  let weather: Weather | null = kept?.verwachting ?? null;
  if (!kept || now.getTime() - new Date(kept.opgehaald).getTime() > WEATHER_MAX_AGE_MS) {
    const location = centroid(field.boundary);
    const response = await env.fetch(openMeteoUrl(location));
    if (response.ok) {
      weather = weatherFromOpenMeteo(await response.json(), field.id, location, now);
      await upsert('weer', { veld: row.id, verwachting: weather, opgehaald: now.toISOString() });
    }
  }

  const since = new Date(now.getTime() - 3 * 86400_000).toISOString();
  const rows = (await rest(
    `sensormetingen?veld=eq.${row.id}&tijd=gte.${since}&select=tijd,ruw,sensoren(sensor_id)&order=tijd.asc`,
  )) as { tijd: string; ruw: number; sensoren: { sensor_id: string } }[];
  const measurements: Measurement[] = rows.map((r) => ({ sensorId: r.sensoren.sensor_id, time: new Date(r.tijd), raw: r.ruw }));

  // The markers of the most recent flight that was analysed.
  const marks = (await rest(
    `aandacht?veld=eq.${row.id}&select=lat,lng,reden,foto,zekerheid,vlucht_id,soort,gezien,gemaakt&order=gemaakt.desc&limit=1000`,
  )) as {
    lat: number; lng: number; reden: string; foto: string | null; zekerheid: number | null; vlucht_id: string;
    soort: string | null; gezien: string | null; gemaakt: string;
  }[];
  const latestFlight = marks[0]?.vlucht_id;
  const attention: Attention[] = marks
    .filter((m) => m.vlucht_id === latestFlight)
    .map((m) => ({
      lat: m.lat, lng: m.lng, reason: m.reden, photoFile: m.foto, flightId: m.vlucht_id, confidence: m.zekerheid,
      kind: m.soort, seenAt: m.gezien || m.gemaakt ? new Date(m.gezien ?? m.gemaakt) : null,
    }));

  await upsert('resultaten', { veld: row.id, resultaten: results(field, measurements, weather, attention, now), berekend: now.toISOString() });
}

/** One run: every field, or only `body.veld` (its uuid). */
/**
 * The key of the database: the new secret key (a JSON list of keys by name), or the older
 * service_role key, which Supabase is phasing out.
 */
export function secretKey(get: (name: string) => string | undefined): string {
  try {
    const keys = JSON.parse(get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>;
    if (keys.default) return keys.default;
  } catch {
    // Not readable: try the older key.
  }
  return get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

export async function work(body: unknown, env: Env): Promise<{ status: number; body: object }> {
  try {
    const wanted = (body as { veld?: unknown } | null)?.veld;
    const one = typeof wanted === 'string' && /^[0-9a-f-]{36}$/i.test(wanted) ? `&id=eq.${wanted}` : '';
    const fields = (await database(env).rest(`velden?select=id,veld_id,veld${one}`)) as FieldRow[];
    const now = env.now?.() ?? new Date();
    const problems: string[] = [];
    for (const field of fields) {
      try {
        await calculate(env, field, now);
      } catch (error) {
        problems.push(`${field.veld_id}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    return { status: 200, body: { berekend: fields.length - problems.length, problemen: problems } };
  } catch (error) {
    return { status: 500, body: { fout: error instanceof Error ? error.message : String(error) } };
  }
}
