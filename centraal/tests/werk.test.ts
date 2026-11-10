// The edge function's work with a fake database and a fake Open-Meteo: it must fetch the
// weather when needed, read the measurements and markers, and store weather and results.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { secretKey, work } from '../supabase/functions/_shared/werk.ts';

const openMeteo = readFileSync(
  new URL('../../ios/VeldvluchtKern/Tests/VeldvluchtKernTests/open-meteo-voorbeeld.json', import.meta.url),
  'utf8',
);

const kLat = 6371008.8 * (Math.PI / 180);
const kLng = kLat * Math.cos(52.5 * (Math.PI / 180));
const at = (x: number, y: number) => ({ lat: 52.5 + y / kLat, lng: 5.54 + x / kLng });
const ID = '11111111-2222-3333-4444-555555555555';
const field = {
  format: 'veldvlucht/veld',
  id: 'proefveld',
  name: 'Proefveld',
  boundary: [at(0, 0), at(100, 0), at(100, 60), at(0, 60)],
  settings: { altitudeM: 30, speedMps: 4, lineSpacingM: 20, photoIntervalS: 3, lineAngleDeg: null, edgeMarginM: 5 },
  sensors: [{ id: 'proefveld-s1', location: at(50, 30), depthCm: 15, calibration: { dryRaw: 860, wetRaw: 340 } }],
  stripWidthM: 24,
};

/** A fake Supabase REST API and Open-Meteo; remembers what was written. */
function fakeServer(options: { weatherAgeMinutes?: number } = {}) {
  const written: Record<string, { body: Record<string, unknown>; headers: Record<string, string> }> = {};
  const asked: string[] = [];
  const now = new Date('2026-10-26T12:00:00+01:00');
  const fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    asked.push(url);
    const json = (data: unknown) => new Response(JSON.stringify(data), { status: 200 });
    if (url.startsWith('https://api.open-meteo.com/')) return new Response(openMeteo, { status: 200 });
    const path = url.replace('https://proef.supabase.co/rest/v1/', '');
    if (init?.method === 'POST') {
      written[path] = { body: JSON.parse(String(init.body)), headers: init.headers as Record<string, string> };
      return new Response(null, { status: 201 });
    }
    if (path.startsWith('velden?')) return json([{ id: ID, veld_id: 'proefveld', veld: field }]);
    if (path.startsWith('weer?')) {
      if (options.weatherAgeMinutes === undefined) return json([]);
      const opgehaald = new Date(now.getTime() - options.weatherAgeMinutes * 60_000).toISOString();
      return json([{ opgehaald, verwachting: { format: 'veld/weer', version: 0, days: [], flightWindows: [] } }]);
    }
    if (path.startsWith('sensormetingen?')) {
      return json([{ tijd: '2026-10-26T10:00:00+01:00', ruw: 760, sensoren: { sensor_id: 'proefveld-s1' } }]);
    }
    if (path.startsWith('aandacht?')) {
      return json([
        {
          lat: 52.50001, lng: 5.5401, reden: 'Geler dan de buren', foto: 'DJI_0042.JPG', zekerheid: 0.6, vlucht_id: 'nieuw',
          soort: 'te-droog', gezien: '2026-10-26T09:30:00+01:00', gemaakt: '2026-10-26T11:00:00+01:00',
        },
        { lat: 52.50002, lng: 5.5402, reden: 'Oud', foto: null, zekerheid: null, vlucht_id: 'oud' },
      ]);
    }
    return new Response('onbekend', { status: 404 });
  };
  return { fetch, written, asked, env: { baseUrl: 'https://proef.supabase.co', key: 'eyJproef', fetch, now: () => now } };
}

describe('the hourly work of the central system', () => {
  it('fetches the weather, works out the advice and stores both', async () => {
    const server = fakeServer();
    const result = await work({}, server.env);
    expect(result).toEqual({ status: 200, body: { berekend: 1, problemen: [] } });

    expect(server.asked.some((u) => u.startsWith('https://api.open-meteo.com/'))).toBe(true);
    const weather = server.written.weer.body as { veld: string; verwachting: { flightWindows: unknown[] } };
    expect(weather.veld).toBe(ID);
    expect(weather.verwachting.flightWindows).toHaveLength(3);

    const stored = server.written.resultaten;
    expect(stored.headers.Prefer).toContain('resolution=merge-duplicates');
    expect(stored.headers.Authorization).toBe('Bearer eyJproef');
    const features = (stored.body.resultaten as { features: { properties: { kind: string; advice?: string; reason?: string } }[] }).features;
    expect(features.map((f) => f.properties.kind)).toEqual(['veldgrens', 'waterzone', 'waterzone', 'waterzone', 'aandacht']);
    // Today (26 October) and tomorrow: 1.1 + 2.0 mm rain in the answer of Open-Meteo.
    expect(features[2].properties.advice).toBe('water');
    expect(features[2].properties.reason).toContain('3,1 mm regen');
    // Only the markers of the most recent flight, with what the AI said and when.
    expect(features[4].properties.reason).toBe('Geler dan de buren');
    expect(features[4].properties).toMatchObject({ plantKind: 'te-droog', seenAt: '2026-10-26T08:30:00.000Z' });
  });

  it('keeps a forecast that is less than an hour old', async () => {
    const server = fakeServer({ weatherAgeMinutes: 20 });
    await work({}, server.env);
    expect(server.asked.some((u) => u.startsWith('https://api.open-meteo.com/'))).toBe(false);
    expect(server.written.weer).toBeUndefined();
    expect(server.written.resultaten).toBeDefined();
  });

  it('can work out one field, and asks only for that one', async () => {
    const server = fakeServer();
    await work({ veld: ID }, server.env);
    expect(server.asked[0]).toContain(`id=eq.${ID}`);
    await work({ veld: "x'; drop table velden" }, server.env);
    expect(server.asked.filter((u) => u.includes('velden?')).at(-1)).not.toContain('drop');
  });

  it('reports a database that does not answer', async () => {
    const result = await work({}, { baseUrl: 'https://proef.supabase.co', key: 'sb_secret_x', fetch: async () => new Response('stuk', { status: 503 }) });
    expect(result.status).toBe(500);
    expect(JSON.stringify(result.body)).toContain('503');
  });
});

describe('secretKey', () => {
  const from = (values: Record<string, string>) => (name: string) => values[name];

  it('prefers the new secret key', () => {
    expect(secretKey(from({ SUPABASE_SECRET_KEYS: '{"default":"sb_secret_a"}', SUPABASE_SERVICE_ROLE_KEY: 'eyJoud' }))).toBe('sb_secret_a');
  });

  it('falls back to the older key', () => {
    expect(secretKey(from({ SUPABASE_SERVICE_ROLE_KEY: 'eyJoud' }))).toBe('eyJoud');
    expect(secretKey(from({ SUPABASE_SECRET_KEYS: 'geen json', SUPABASE_SERVICE_ROLE_KEY: 'eyJoud' }))).toBe('eyJoud');
    expect(secretKey(from({}))).toBe('');
  });
});
