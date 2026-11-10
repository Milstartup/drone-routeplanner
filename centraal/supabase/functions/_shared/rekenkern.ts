// The calculations of the central system, the same as in the app (ios/VeldvluchtKern:
// FieldRecord.swift, OpenMeteo.swift, WaterAdvisor.swift): the watering strips of a field,
// the weather of Open-Meteo with the moments to fly, and the water advice per strip.
// Plain TypeScript without Deno or Node, so the edge function runs it and the tests check it
// with the same cases as the Swift tests (centraal/tests/rekenkern.test.ts).

export interface LatLng {
  lat: number;
  lng: number;
}

interface XY {
  x: number;
  y: number;
}

/** A field as the app keeps it (format veldvlucht/veld); only what the calculations need. */
export interface FieldRecord {
  id: string;
  name: string;
  boundary: LatLng[];
  settings: { lineAngleDeg?: number | null };
  sensors: { id: string; location: LatLng; depthCm?: number; calibration?: Calibration | null }[];
  stripWidthM?: number;
}

export interface Calibration {
  dryRaw: number;
  wetRaw: number;
}

export interface Measurement {
  sensorId: string;
  time: Date;
  raw: number;
}

export interface WeatherDay {
  date: string;
  precipitationMm: number;
  tempMinC: number;
  tempMaxC: number;
  windMaxMps: number;
  gustMaxMps: number;
  evaporationMm?: number | null;
}

export interface FlightWindow {
  start: string;
  end: string;
  reason: string;
}

/** Format veld/weer. */
export interface Weather {
  format: 'veld/weer';
  version: 0;
  fieldId: string;
  location: LatLng;
  source: string;
  attribution: string;
  createdAt: string;
  days: WeatherDay[];
  flightWindows: FlightWindow[];
}

export type Advice = 'genoeg' | 'binnenkort' | 'water';

/** A plant or spot that needs attention, from the photo analysis. */
export interface Attention {
  lat: number;
  lng: number;
  reason: string;
  photoFile?: string | null;
  flightId: string;
  confidence?: number | null;
  /** What the AI says the plant is: 'te-droog', 'te-nat', 'ziek-of-beschadigd', 'gezond', 'geen-plant'. */
  kind?: string | null;
  /** When the photo was taken. */
  seenAt?: Date | null;
}

const EARTH_RADIUS_M = 6371008.8;
const DEG = Math.PI / 180;
const DEFAULT_STRIP_WIDTH_M = 24;

// ---- Geometry (src/core/geo.ts, Geo.swift) ----

export function centroid(points: LatLng[]): LatLng {
  if (points.length === 0) return { lat: 0, lng: 0 };
  return {
    lat: points.reduce((s, p) => s + p.lat, 0) / points.length,
    lng: points.reduce((s, p) => s + p.lng, 0) / points.length,
  };
}

function projection(origin: LatLng) {
  const kLat = EARTH_RADIUS_M * DEG;
  const kLng = kLat * Math.cos(origin.lat * DEG);
  return {
    toXY: (p: LatLng): XY => ({ x: (p.lng - origin.lng) * kLng, y: (p.lat - origin.lat) * kLat }),
    toLatLng: (p: XY): LatLng => ({ lat: origin.lat + p.y / kLat, lng: origin.lng + p.x / kLng }),
  };
}

function pointInPolygon(p: XY, poly: XY[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i];
    const b = poly[j];
    if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}

function distanceToEdges(p: XY, poly: XY[]): number {
  let best = Infinity;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const ex = b.x - a.x;
    const ey = b.y - a.y;
    const len2 = ex * ex + ey * ey;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * ex + (p.y - a.y) * ey) / len2));
    best = Math.min(best, Math.hypot(p.x - (a.x + t * ex), p.y - (a.y + t * ey)));
  }
  return best;
}

function areaXY(poly: XY[]): number {
  let twice = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return Math.abs(twice) / 2;
}

/** Bearing of the flight lines: the setting, or along the longest edge (src/core/coverage.ts). */
export function lineAngle(field: FieldRecord): number {
  const setting = field.settings.lineAngleDeg;
  const normalize = (d: number) => {
    const r = d % 180;
    return r < 0 ? r + 180 : r;
  };
  if (setting != null && Number.isFinite(setting)) return normalize(setting);
  if (field.boundary.length < 3) return 0;
  const proj = projection(centroid(field.boundary));
  const poly = field.boundary.map(proj.toXY);
  let best = 0;
  let bestLength = -1;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const length = Math.hypot(b.x - a.x, b.y - a.y);
    if (length > bestLength) {
      bestLength = length;
      best = Math.atan2(b.x - a.x, b.y - a.y) / DEG;
    }
  }
  return normalize(best);
}

// ---- Strips (FieldStrips in FieldRecord.swift) ----

/** The field cut into strips of `widthM` along `angleDeg`, from one edge to the other. */
export function strips(boundary: LatLng[], angleDeg: number, widthM: number): LatLng[][] {
  if (boundary.length < 3 || !(widthM > 0)) return [];
  const proj = projection(centroid(boundary));
  const s = Math.sin(angleDeg * DEG);
  const c = Math.cos(angleDeg * DEG);
  const rotated = boundary.map(proj.toXY).map((p) => ({ x: p.x * s + p.y * c, y: -p.x * c + p.y * s }));
  const toLatLng = (p: XY) => proj.toLatLng({ x: p.x * s - p.y * c, y: p.x * c + p.y * s });
  const ys = rotated.map((p) => p.y);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  if (!(maxY > minY)) return [];
  const count = Math.min(500, Math.ceil((maxY - minY) / widthM));
  const result: LatLng[][] = [];
  for (let k = 0; k < count; k++) {
    const y0 = minY + k * widthM;
    const y1 = Math.min(maxY, y0 + widthM);
    const piece = clip(clip(rotated, (p) => p.y >= y0, y0), (p) => p.y <= y1, y1);
    if (piece.length >= 3 && areaXY(piece) >= 1) result.push(piece.map(toLatLng));
  }
  return result;
}

/** Sutherland–Hodgman against one horizontal line. */
function clip(points: XY[], keep: (p: XY) => boolean, y: number): XY[] {
  const out: XY[] = [];
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    if (keep(a)) out.push(a);
    if (keep(a) !== keep(b) && b.y !== a.y) {
      const t = (y - a.y) / (b.y - a.y);
      out.push({ x: a.x + (b.x - a.x) * t, y });
    }
  }
  return out;
}

// ---- Weather (OpenMeteo.swift) ----

export const OPEN_METEO_ATTRIBUTION = 'Weergegevens door Open-Meteo.com (CC BY 4.0)';
const MAX_WIND_MPS = 5;
const MAX_GUST_MPS = 7;
const MIN_HOURS = 2;

export function openMeteoUrl(location: LatLng, days = 5): string {
  const query = new URLSearchParams({
    latitude: location.lat.toFixed(4),
    longitude: location.lng.toFixed(4),
    hourly: 'precipitation,wind_speed_10m,wind_gusts_10m,is_day',
    daily: 'precipitation_sum,temperature_2m_min,temperature_2m_max,wind_speed_10m_max,wind_gusts_10m_max,et0_fao_evapotranspiration',
    wind_speed_unit: 'ms',
    timezone: 'Europe/Amsterdam',
    forecast_days: String(days),
  });
  return `https://api.open-meteo.com/v1/forecast?${query}`;
}

/** Offset of a time zone from UTC at an instant, in milliseconds. */
function zoneOffsetMs(instant: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(instant));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second')) - instant;
}

/** "2026-10-28T08:00" in the given time zone → the instant. */
function localTime(text: string, timeZone: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(text);
  if (!m) return null;
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
  let instant = asUtc - zoneOffsetMs(asUtc, timeZone);
  instant = asUtc - zoneOffsetMs(instant, timeZone);
  return new Date(instant);
}

/** The date in Dutch time, "2026-10-26". */
function dutchDate(date: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Amsterdam', year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

interface OpenMeteoAnswer {
  timezone: string;
  hourly: {
    time: string[];
    precipitation: (number | null)[];
    wind_speed_10m: (number | null)[];
    wind_gusts_10m: (number | null)[];
    is_day: (number | null)[];
  };
  daily: {
    time: string[];
    precipitation_sum: (number | null)[];
    temperature_2m_min: (number | null)[];
    temperature_2m_max: (number | null)[];
    wind_speed_10m_max: (number | null)[];
    wind_gusts_10m_max: (number | null)[];
    et0_fao_evapotranspiration: (number | null)[];
  };
}

/** Open-Meteo's answer in the format veld/weer, with the moments that are good for flying. */
export function weatherFromOpenMeteo(answer: OpenMeteoAnswer, fieldId: string, location: LatLng, now: Date): Weather {
  const d = answer.daily;
  const days: WeatherDay[] = d.time.map((date, i) => ({
    date,
    precipitationMm: d.precipitation_sum[i] ?? 0,
    tempMinC: d.temperature_2m_min[i] ?? 0,
    tempMaxC: d.temperature_2m_max[i] ?? 0,
    windMaxMps: d.wind_speed_10m_max[i] ?? 0,
    gustMaxMps: d.wind_gusts_10m_max[i] ?? 0,
    evaporationMm: d.et0_fao_evapotranspiration[i] ?? null,
  }));
  const h = answer.hourly;
  const hours = h.time.flatMap((text, i) => {
    const start = localTime(text, answer.timezone || 'Europe/Amsterdam');
    if (!start) return [];
    return [{
      start,
      precipitationMm: h.precipitation[i] ?? Infinity,
      windMps: h.wind_speed_10m[i] ?? Infinity,
      gustMps: h.wind_gusts_10m[i] ?? Infinity,
      isDay: h.is_day[i] === 1,
    }];
  });
  return {
    format: 'veld/weer',
    version: 0,
    fieldId,
    location,
    source: 'Open-Meteo',
    attribution: OPEN_METEO_ATTRIBUTION,
    createdAt: now.toISOString(),
    days,
    flightWindows: flightWindows(hours, now),
  };
}

interface Hour {
  start: Date;
  precipitationMm: number;
  windMps: number;
  gustMps: number;
  isDay: boolean;
}

/** Runs of at least two good hours from now on, soonest first (FlightWeather.windows). */
export function flightWindows(hours: Hour[], now: Date): FlightWindow[] {
  const good = (h: Hour) => h.isDay && h.precipitationMm < 0.05 && h.windMps < MAX_WIND_MPS && h.gustMps < MAX_GUST_MPS;
  const windows: FlightWindow[] = [];
  let run: Hour[] = [];
  const close = () => {
    if (run.length >= MIN_HOURS) {
      const wind = Math.max(...run.map((h) => h.windMps));
      const gust = Math.max(...run.map((h) => h.gustMps));
      windows.push({
        start: run[0].start.toISOString(),
        end: new Date(run[run.length - 1].start.getTime() + 3600_000).toISOString(),
        reason: `Wind tot ${Math.round(wind)} m/s met windstoten tot ${Math.round(gust)} m/s, droog en daglicht.`,
      });
    }
    run = [];
  };
  for (const hour of [...hours].sort((a, b) => a.start.getTime() - b.start.getTime())) {
    if (hour.start.getTime() + 3600_000 <= now.getTime()) continue;
    const last = run[run.length - 1];
    if (good(hour) && (!last || hour.start.getTime() - last.start.getTime() <= 3600_000)) {
      run.push(hour);
    } else {
      close();
      if (good(hour)) run.push(hour);
    }
  }
  close();
  return windows;
}

// ---- Water advice (WaterAdvisor.swift) ----

const DRY_BELOW = 35;
const ENOUGH_FROM = 50;
const TARGET = 55;
const MM_PER_PERCENT = 0.4;
const MAX_AGE_S = 48 * 3600;
const RAIN_WAIT_MM = 10;
const NET_RAIN_ENOUGH_MM = 5;

/** Moisture between dry (0 %) and saturated (100 %) soil; works both ways round. */
export function moisturePercent(calibration: Calibration | null | undefined, raw: number): number | null {
  if (!calibration || Math.abs(calibration.dryRaw - calibration.wetRaw) < 1) return null;
  const p = ((raw - calibration.dryRaw) / (calibration.wetRaw - calibration.dryRaw)) * 100;
  return Math.min(100, Math.max(0, p));
}

/** "zojuist", "45 min geleden", "3 uur geleden", "2 dagen geleden" (FieldSummary.ageText). */
export function ageText(date: Date, now: Date): string {
  const seconds = (now.getTime() - date.getTime()) / 1000;
  if (seconds < 0) return 'in de toekomst';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 2) return 'zojuist';
  if (minutes < 60) return `${minutes} min geleden`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return hours === 1 ? '1 uur geleden' : `${hours} uur geleden`;
  return `${Math.floor(hours / 24)} dagen geleden`;
}

/** 2 → "2", 2.4 → "2,4" (RouteCheck.number). */
function number(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(1).replace('.', ',');
}

const round1 = (value: number) => Math.round(value * 10) / 10;

/** Rain and evaporation expected today and tomorrow (Dutch time). */
export function expectedWater(weather: Weather | null, now: Date): { rainMm: number; evaporationMm: number } | null {
  if (!weather) return null;
  const today = dutchDate(now);
  const days = weather.days.filter((d) => d.date >= today).sort((a, b) => a.date.localeCompare(b.date)).slice(0, 2);
  if (days.length === 0) return null;
  return {
    rainMm: days.reduce((s, d) => s + d.precipitationMm, 0),
    evaporationMm: days.reduce((s, d) => s + (d.evaporationMm ?? 0), 0),
  };
}

interface StripAdvice {
  advice?: Advice;
  amountMm?: number;
  reason: string;
  confidence?: number;
}

// ---- Photos in the advice (WaterAdvisor.swift, combine) ----

/** Photos older than this say nothing about the water now. */
const PHOTO_MAX_AGE_S = 7 * 24 * 3600;
/** This many plants the AI found too dry (or too wet) in one strip count for the advice. */
const PHOTO_MIN_PLANTS = 3;

interface PhotoEvidence {
  dry: number;
  wet: number;
  newest: Date | null;
}

function photoEvidence(polygon: XY[], attention: Attention[], proj: ReturnType<typeof projection>, now: Date): PhotoEvidence {
  const evidence: PhotoEvidence = { dry: 0, wet: 0, newest: null };
  for (const mark of attention) {
    const seen = mark.seenAt;
    if (!seen || seen > now || (now.getTime() - seen.getTime()) / 1000 > PHOTO_MAX_AGE_S) continue;
    if (!pointInPolygon(proj.toXY({ lat: mark.lat, lng: mark.lng }), polygon)) continue;
    if (mark.kind === 'te-droog') evidence.dry += 1;
    else if (mark.kind === 'te-nat') evidence.wet += 1;
    else continue;
    if (!evidence.newest || seen > evidence.newest) evidence.newest = seen;
  }
  return evidence;
}

const looksDry = (e: PhotoEvidence) => e.dry >= PHOTO_MIN_PLANTS && e.wet < PHOTO_MIN_PLANTS;
const looksWet = (e: PhotoEvidence) => e.wet >= PHOTO_MIN_PLANTS && e.dry < PHOTO_MIN_PLANTS;

function photoText(e: PhotoEvidence, now: Date): string | null {
  if (!e.newest) return null;
  const parts = [
    e.dry >= PHOTO_MIN_PLANTS ? `${e.dry} planten lijken te droog` : null,
    e.wet >= PHOTO_MIN_PLANTS ? `${e.wet} planten lijken te nat` : null,
  ].filter((p): p is string => p !== null);
  if (parts.length === 0) return null;
  return `Foto's van ${ageText(e.newest, now)}: ${parts.join(' en ')} (AI).`;
}

/**
 * The sensor's advice, checked against the photos. Agreeing photos make it surer; photos that
 * disagree send the farmer to look first. Without a usable sensor the photos alone give a
 * careful advice.
 */
function combine(sensor: StripAdvice, photos: PhotoEvidence, now: Date): StripAdvice {
  const text = photoText(photos, now);
  if (!text) return sensor;
  const result: StripAdvice = { ...sensor, reason: `${sensor.reason} ${text}` };
  if (!sensor.advice) {
    if (looksDry(photos)) {
      return {
        advice: 'binnenkort',
        amountMm: 0,
        reason: `${result.reason} Zonder meting → binnenkort water geven. Een sensor maakt het advies zekerder.`,
        confidence: 0.3,
      };
    }
    if (looksWet(photos)) {
      return { advice: 'genoeg', amountMm: 0, reason: `${result.reason} Zonder meting → geen water geven.`, confidence: 0.3 };
    }
    return result;
  }
  let confidence = sensor.confidence ?? 0.5;
  if (sensor.advice === 'genoeg' && looksDry(photos)) {
    result.advice = 'binnenkort';
    result.reason += ' De sensor meet genoeg: kijk in het veld of de sensor goed in de grond zit → binnenkort.';
    confidence -= 0.1;
  } else if (sensor.advice === 'water' && looksWet(photos)) {
    result.advice = 'binnenkort';
    result.reason += ' De sensor meet droog: kijk eerst in het veld → binnenkort.';
    confidence -= 0.1;
  } else if (sensor.advice === 'binnenkort' && looksWet(photos)) {
    result.reason += ' Dat past niet bij de sensor: kijk eerst in het veld.';
    confidence -= 0.1;
  } else if ((sensor.advice !== 'genoeg' && looksDry(photos)) || (sensor.advice === 'genoeg' && looksWet(photos))) {
    result.reason += ' Dat past bij de sensor.';
    confidence += 0.1;
  }
  result.confidence = Math.min(0.8, Math.max(0.2, Math.round(confidence * 1e9) / 1e9));
  return result;
}

function shortName(sensorId: string, fieldId: string): string {
  return sensorId.startsWith(`${fieldId}-`) ? sensorId.slice(fieldId.length + 1) : sensorId;
}

function adviseStrip(
  strip: LatLng[],
  field: FieldRecord,
  latest: Map<string, Measurement>,
  water: { rainMm: number; evaporationMm: number } | null,
  proj: ReturnType<typeof projection>,
  now: Date,
): StripAdvice {
  const polygon = strip.map(proj.toXY);
  const width = field.stripWidthM ?? DEFAULT_STRIP_WIDTH_M;
  let near = false;
  let sensors = field.sensors.filter((s) => pointInPolygon(proj.toXY(s.location), polygon));
  if (sensors.length === 0) {
    let best: { sensor: FieldRecord['sensors'][number]; distance: number } | null = null;
    for (const sensor of field.sensors) {
      const distance = distanceToEdges(proj.toXY(sensor.location), polygon);
      if (!best || distance < best.distance) best = { sensor, distance };
    }
    if (best && best.distance <= width) {
      sensors = [best.sensor];
      near = true;
    }
  }
  if (sensors.length === 0) return { reason: 'Geen sensor in of naast deze strook. Plaats er een bij Sensoren.' };

  const readings: { name: string; percent: number; time: Date }[] = [];
  for (const sensor of sensors) {
    const name = shortName(sensor.id, field.id);
    const m = latest.get(sensor.id);
    if (!m) return { reason: `Sensor ${name} heeft nog geen meting gestuurd.` };
    if ((now.getTime() - m.time.getTime()) / 1000 > MAX_AGE_S) {
      return { reason: `De laatste meting van sensor ${name} is van ${ageText(m.time, now)}. Voor advies is een meting van de laatste 2 dagen nodig.` };
    }
    const percent = moisturePercent(sensor.calibration, m.raw);
    if (percent === null) {
      return { reason: `Sensor ${name} is nog niet geijkt (ruwe waarde ${Math.round(m.raw)}). IJk hem bij Sensoren: meet droge en natte grond van dit veld.` };
    }
    readings.push({ name, percent, time: m.time });
  }
  const moisture = readings.reduce((s, r) => s + r.percent, 0) / readings.length;
  const newest = new Date(Math.max(...readings.map((r) => r.time.getTime())));

  const sensorText = readings.map((r) => `${r.name} ${Math.round(r.percent)} % vocht`).join(', ');
  let reason = `Sensor ${sensorText}, gemeten ${ageText(newest, now)}${near ? ' (naast deze strook)' : ''}.`;
  const rain = water?.rainMm ?? 0;
  const net = rain - (water?.evaporationMm ?? 0);
  if (water) {
    reason += ` Verwacht vandaag en morgen ${number(round1(water.rainMm))} mm regen en ${number(round1(water.evaporationMm))} mm verdamping.`;
  } else {
    reason += ' Geen weersverwachting: regen telt niet mee.';
  }

  let advice: Advice;
  let amount = 0;
  const needed = Math.max(0, (TARGET - moisture) * MM_PER_PERCENT);
  if (moisture < DRY_BELOW) {
    if (rain >= RAIN_WAIT_MM) {
      advice = 'binnenkort';
      amount = Math.max(0, needed - rain);
      reason += ` Regel: droger dan ${DRY_BELOW} %, maar ${RAIN_WAIT_MM} mm regen of meer op komst → wacht op de regen en kijk morgen opnieuw.`;
    } else {
      advice = 'water';
      amount = needed;
      reason += ` Regel: droger dan ${DRY_BELOW} % en weinig regen op komst → nu water geven.`;
    }
  } else if (moisture < ENOUGH_FROM) {
    if (net >= NET_RAIN_ENOUGH_MM) {
      advice = 'genoeg';
      reason += ` Regel: tussen ${DRY_BELOW} en ${ENOUGH_FROM} %, maar ${NET_RAIN_ENOUGH_MM} mm meer regen dan verdamping → genoeg.`;
    } else {
      advice = 'binnenkort';
      amount = needed;
      reason += ` Regel: tussen ${DRY_BELOW} en ${ENOUGH_FROM} % en weinig regen → binnenkort water geven.`;
    }
  } else {
    advice = 'genoeg';
    reason += ` Regel: ${ENOUGH_FROM} % of natter → genoeg.`;
  }

  let confidence = near ? 0.4 : 0.6;
  if ((now.getTime() - newest.getTime()) / 1000 < 12 * 3600) confidence += 0.1;
  if (!water) confidence -= 0.1;
  return {
    advice,
    amountMm: amount > 0 ? Math.round(amount * 2) / 2 : 0,
    reason,
    confidence: Math.min(0.8, Math.max(0.2, Math.round(confidence * 1e9) / 1e9)),
  };
}

const ring = (points: LatLng[]): number[][] => {
  const coordinates = points.map((p) => [p.lng, p.lat]);
  const first = coordinates[0];
  const last = coordinates[coordinates.length - 1];
  if (first && (first[0] !== last[0] || first[1] !== last[1])) coordinates.push([...first]);
  return coordinates;
};

/** Format veld/resultaten: the field boundary, the strips with advice and the attention markers. */
export function results(field: FieldRecord, measurements: Measurement[], weather: Weather | null, attention: Attention[], now: Date) {
  const latest = new Map<string, Measurement>();
  for (const m of measurements) {
    const known = latest.get(m.sensorId);
    if (!known || m.time > known.time) latest.set(m.sensorId, m);
  }
  const water = expectedWater(weather, now);
  const proj = projection(centroid(field.boundary));
  const features: object[] = [];
  if (field.boundary.length >= 3) {
    features.push({
      type: 'Feature',
      geometry: { type: 'Polygon', coordinates: [ring(field.boundary)] },
      properties: { kind: 'veldgrens', name: field.name },
    });
  }
  strips(field.boundary, lineAngle(field), field.stripWidthM ?? DEFAULT_STRIP_WIDTH_M).forEach((strip, index) => {
    const photos = photoEvidence(strip.map(proj.toXY), attention, proj, now);
    const a = combine(adviseStrip(strip, field, latest, water, proj, now), photos, now);
    features.push({
      type: 'Feature',
      geometry: { type: 'Polygon', coordinates: [ring(strip)] },
      properties: { kind: 'waterzone', name: `Strook ${index + 1}`, ...a },
    });
  });
  for (const mark of attention) {
    features.push({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [mark.lng, mark.lat] },
      properties: {
        kind: 'aandacht',
        reason: mark.reason,
        photoFile: mark.photoFile ?? undefined,
        flightId: mark.flightId,
        confidence: mark.confidence ?? undefined,
        plantKind: mark.kind ?? undefined,
        seenAt: mark.seenAt?.toISOString(),
      },
    });
  }
  return {
    type: 'FeatureCollection',
    properties: { format: 'veld/resultaten', version: 0, fieldId: field.id, createdAt: now.toISOString() },
    features,
  };
}
