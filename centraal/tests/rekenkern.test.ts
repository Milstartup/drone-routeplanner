// The same cases as CentralTests.swift in the app: the central system in the cloud must give
// the same weather windows and the same advice, with the same reasons, as the app.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  type FieldRecord,
  type LatLng,
  type Measurement,
  type Weather,
  results,
  strips,
  weatherFromOpenMeteo,
} from '../supabase/functions/_shared/rekenkern.ts';

const answer = JSON.parse(
  readFileSync(new URL('../../ios/VeldvluchtKern/Tests/VeldvluchtKernTests/open-meteo-voorbeeld.json', import.meta.url), 'utf8'),
);
const date = (text: string) => new Date(text);

describe('weather of Open-Meteo', () => {
  it('reads the days and finds the moments to fly', () => {
    const weather = weatherFromOpenMeteo(answer, 'veld-noord', { lat: 52.499, lng: 5.5425 }, date('2026-10-26T12:00:00+01:00'));
    expect(weather.days.map((d) => d.date)).toEqual(['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30']);
    expect(weather.days[1].precipitationMm).toBe(2.0);
    expect(weather.days[0].gustMaxMps).toBe(17.4);
    expect(weather.days[0].evaporationMm).toBe(1.4);
    expect(weather.flightWindows).toHaveLength(3);
    expect(weather.flightWindows[0].start).toBe(date('2026-10-28T08:00:00+01:00').toISOString());
    expect(weather.flightWindows[0].end).toBe(date('2026-10-28T11:00:00+01:00').toISOString());
    expect(weather.flightWindows[1].start).toBe(date('2026-10-29T08:00:00+01:00').toISOString());
    expect(weather.flightWindows[1].end).toBe(date('2026-10-29T18:00:00+01:00').toISOString());
    expect(weather.flightWindows[0].reason).toContain('windstoten tot 6 m/s');
  });

  it('counts a window that has started from the current hour', () => {
    const weather = weatherFromOpenMeteo(answer, 'veld-noord', { lat: 52.5, lng: 5.54 }, date('2026-10-29T12:30:00+01:00'));
    expect(weather.flightWindows[0].start).toBe(date('2026-10-29T12:00:00+01:00').toISOString());
    expect(weather.flightWindows[0].end).toBe(date('2026-10-29T18:00:00+01:00').toISOString());
  });
});

// A 100 m (east-west) by 60 m field with one sensor in the middle, as in CentralTests.swift.
const kLat = 6371008.8 * (Math.PI / 180);
const kLng = kLat * Math.cos(52.5 * (Math.PI / 180));
const at = (x: number, y: number): LatLng => ({ lat: 52.5 + y / kLat, lng: 5.54 + x / kLng });

function field(calibrated = true): FieldRecord {
  return {
    id: 'proefveld',
    name: 'Proefveld',
    boundary: [at(0, 0), at(100, 0), at(100, 60), at(0, 60)],
    settings: { lineAngleDeg: null },
    sensors: [{ id: 'proefveld-s1', location: at(50, 30), calibration: calibrated ? { dryRaw: 860, wetRaw: 340 } : null }],
  };
}

function weather(rainToday: number, rainTomorrow: number, evaporation = 1): Weather {
  const day = (d: string, rain: number, evap: number) => ({
    date: d, precipitationMm: rain, tempMinC: 5, tempMaxC: 10, windMaxMps: 3, gustMaxMps: 5, evaporationMm: evap,
  });
  return {
    format: 'veld/weer', version: 0, fieldId: 'proefveld', location: at(50, 30), source: 'test', attribution: 'test',
    createdAt: '2026-10-26T05:00:00Z', flightWindows: [],
    days: [day('2026-10-25', 30, 1), day('2026-10-26', rainToday, evaporation), day('2026-10-27', rainTomorrow, evaporation)],
  };
}

type Zone = { properties: { name: string; advice?: string; amountMm?: number; confidence?: number; reason: string } };

function advice(raw: number, w: Weather | null, time = '2026-10-26T10:00:00+01:00', calibrated = true): Zone[] {
  const measurements: Measurement[] = [{ sensorId: 'proefveld-s1', time: date(time), raw }];
  const r = results(field(calibrated), measurements, w, [], date('2026-10-26T12:00:00+01:00'));
  const features = r.features as { properties: { kind: string; name?: string } }[];
  expect(features[0].properties).toEqual({ kind: 'veldgrens', name: 'Proefveld' });
  return features.filter((f) => f.properties.kind === 'waterzone') as unknown as Zone[];
}

describe('water advice per strip', () => {
  it('cuts the field into strips along the flight lines', () => {
    const zones = advice(600, weather(0, 0));
    expect(zones.map((z) => z.properties.name)).toEqual(['Strook 1', 'Strook 2', 'Strook 3']);
    expect(strips(field().boundary, 90, 24)).toHaveLength(3);
  });

  it('dry and no rain: water now', () => {
    const zones = advice(760, weather(0.5, 0.5));
    const middle = zones[1].properties;
    expect(middle.advice).toBe('water');
    expect(middle.amountMm).toBe(14.5);
    expect(middle.confidence).toBeCloseTo(0.7, 9);
    expect(middle.reason).toBe(
      'Sensor s1 19 % vocht, gemeten 2 uur geleden. Verwacht vandaag en morgen 1 mm regen en 2 mm verdamping. ' +
        'Regel: droger dan 35 % en weinig regen op komst → nu water geven.',
    );
    expect(zones[0].properties.advice).toBe('water');
    expect(zones[0].properties.confidence).toBeCloseTo(0.5, 9);
    expect(zones[0].properties.reason).toContain('naast deze strook');
  });

  it('dry but much rain coming: wait', () => {
    const zone = advice(760, weather(4, 8))[1].properties;
    expect(zone.advice).toBe('binnenkort');
    expect(zone.reason).toContain('wacht op de regen');
  });

  it('in between', () => {
    expect(advice(620, weather(1, 0))[1].properties.advice).toBe('binnenkort');
    expect(advice(620, weather(4, 4))[1].properties.advice).toBe('genoeg');
  });

  it('wet enough', () => {
    const zone = advice(500, weather(0, 0))[1].properties;
    expect(zone.advice).toBe('genoeg');
    expect(zone.amountMm).toBe(0);
  });

  it('no advice without calibration or with an old measurement', () => {
    const uncalibrated = advice(760, weather(0, 0), undefined, false)[1].properties;
    expect(uncalibrated.advice).toBeUndefined();
    expect(uncalibrated.reason).toContain('nog niet geijkt');
    const old = advice(760, weather(0, 0), '2026-10-23T10:00:00+02:00')[1].properties;
    expect(old.advice).toBeUndefined();
    expect(old.reason).toContain('laatste 2 dagen');
  });

  it('without weather rain does not count', () => {
    const zone = advice(760, null)[1].properties;
    expect(zone.advice).toBe('water');
    expect(zone.confidence).toBeCloseTo(0.6, 9);
    expect(zone.reason).toContain('Geen weersverwachting');
  });

  it('adds the plants that need attention', () => {
    const r = results(field(), [], null, [{ lat: 52.5001, lng: 5.5402, reason: 'Geler dan de buren', photoFile: 'DJI_0042.JPG', flightId: 'v1', confidence: 0.6 }], new Date());
    const marks = (r.features as { geometry: { type: string; coordinates: number[] }; properties: { kind: string } }[])
      .filter((f) => f.properties.kind === 'aandacht');
    expect(marks).toHaveLength(1);
    expect(marks[0].geometry).toEqual({ type: 'Point', coordinates: [5.5402, 52.5001] });
  });
});
