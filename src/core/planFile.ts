// Saving and loading plans as JSON with GPS coordinates (WGS84).
//
// This is the planner's own file format. It is NOT a DJI mission file: no DJI app or
// drone can execute it directly. A future drone app has to read it, check it again and
// translate it into its own commands.
import type { PlanAnalysis } from './analysis';
import { DEFAULT_ASSUMPTIONS } from './defaults';
import { isValidLatLng } from './geo';
import type { Assumptions, FlightSettings, LatLng, Plan, PlanMode } from './types';

export const PLAN_FILE_FORMAT = 'drone-routeplanner/plan';
export const PLAN_FILE_VERSION = 1;
export const PLAN_FILE_NOTICE =
  'Planningsbestand van de drone-routeplanner (prototype). Dit is GEEN DJI-missiebestand en kan niet ' +
  'rechtstreeks door een DJI-drone of DJI-app worden uitgevoerd. Een toekomstige drone-app moet de route ' +
  'zelf inlezen, opnieuw controleren en omzetten naar eigen commando\'s.';

export interface PlanFileV1 {
  format: typeof PLAN_FILE_FORMAT;
  version: typeof PLAN_FILE_VERSION;
  notice: string;
  createdAt: string;
  coordinateSystem: string;
  altitudeReference: string;
  name: string;
  mode: PlanMode;
  settings: FlightSettings;
  assumptions: Assumptions;
  home: LatLng | null;
  boundary: LatLng[];
  routePoints: (LatLng & { capture: boolean })[];
  /** Derived from the inputs above when saving; ignored (recalculated) when loading. */
  derived: {
    waypoints: { index: number; lat: number; lng: number; altitudeM: number }[];
    legs: { from: number; to: number; capture: boolean }[];
    photoPoints: { index: number; lat: number; lng: number; legIndex: number }[];
    estimate: {
      totalDistanceM: number;
      flightTimeS: number;
      photoCount: number;
      photoSpacingM: number;
      fieldAreaM2: number | null;
    };
  };
}

const round7 = (n: number) => Math.round(n * 1e7) / 1e7;
const round2 = (n: number) => Math.round(n * 100) / 100;
const ll = (p: LatLng): LatLng => ({ lat: round7(p.lat), lng: round7(p.lng) });

export function createPlanFile(plan: Plan, analysis: PlanAnalysis, now: Date = new Date()): PlanFileV1 {
  const { route, photos, estimate } = analysis;
  return {
    format: PLAN_FILE_FORMAT,
    version: PLAN_FILE_VERSION,
    notice: PLAN_FILE_NOTICE,
    createdAt: now.toISOString(),
    coordinateSystem: 'WGS84 (EPSG:4326), decimale graden',
    altitudeReference: 'meter boven het startpunt',
    name: plan.name,
    mode: plan.mode,
    settings: { ...plan.settings },
    assumptions: { ...plan.assumptions },
    home: plan.home ? ll(plan.home) : null,
    boundary: plan.boundary.map(ll),
    routePoints: plan.routePoints.map((p) => ({ ...ll(p), capture: p.capture })),
    derived: {
      waypoints: route.waypoints.map((p, index) => ({ index, ...ll(p), altitudeM: plan.settings.altitudeM })),
      legs: route.legs.map((leg, i) => ({ from: i, to: i + 1, capture: leg.capture })),
      photoPoints: photos.map((p) => ({ index: p.index, ...ll(p), legIndex: p.legIndex })),
      estimate: {
        totalDistanceM: round2(estimate.totalDistanceM),
        flightTimeS: round2(estimate.totalS),
        photoCount: estimate.photoCount,
        photoSpacingM: round2(estimate.photoSpacingM),
        fieldAreaM2: estimate.fieldAreaM2 === null ? null : round2(estimate.fieldAreaM2),
      },
    },
  };
}

export function serializePlanFile(file: PlanFileV1): string {
  return JSON.stringify(file, null, 2);
}

export type ParseResult = { ok: true; plan: Plan } | { ok: false; error: string };

class FileError extends Error {}

function readNumber(obj: Record<string, unknown>, key: string, path: string): number {
  const v = obj[key];
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new FileError(`Veld "${path}.${key}" moet een getal zijn.`);
  return v;
}

function readPoints(value: unknown, path: string): LatLng[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new FileError(`Veld "${path}" moet een lijst met punten zijn.`);
  return value.map((p, i) => {
    if (!isValidLatLng(p)) throw new FileError(`Punt ${i + 1} in "${path}" heeft geen geldige GPS-coördinaten (lat −90..90, lng −180..180).`);
    return { lat: p.lat, lng: p.lng };
  });
}

function asObject(value: unknown, path: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new FileError(`Veld "${path}" ontbreekt of is geen object.`);
  }
  return value as Record<string, unknown>;
}

/** Reads a plan file. Only the inputs are used; the route is recalculated from them. */
export function parsePlanFile(text: string, makeId: () => string): ParseResult {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return { ok: false, error: 'Dit is geen geldig JSON-bestand.' };
  }
  try {
    const root = asObject(data, '(bestand)');
    if (root.format !== PLAN_FILE_FORMAT) {
      throw new FileError(`Dit is geen routebestand van deze planner (verwacht "format": "${PLAN_FILE_FORMAT}").`);
    }
    if (root.version !== PLAN_FILE_VERSION) {
      throw new FileError(`Onbekende bestandsversie ${String(root.version)}; deze planner leest versie ${PLAN_FILE_VERSION}.`);
    }
    const mode = root.mode;
    if (mode !== 'route' && mode !== 'field') throw new FileError('Veld "mode" moet "route" of "field" zijn.');

    const s = asObject(root.settings, 'settings');
    const angle = s.lineAngleDeg;
    if (angle !== null && (typeof angle !== 'number' || !Number.isFinite(angle))) {
      throw new FileError('Veld "settings.lineAngleDeg" moet een getal of null zijn.');
    }
    const settings: FlightSettings = {
      altitudeM: readNumber(s, 'altitudeM', 'settings'),
      speedMps: readNumber(s, 'speedMps', 'settings'),
      lineSpacingM: readNumber(s, 'lineSpacingM', 'settings'),
      photoIntervalS: readNumber(s, 'photoIntervalS', 'settings'),
      lineAngleDeg: angle as number | null,
      edgeMarginM: readNumber(s, 'edgeMarginM', 'settings'),
    };

    let assumptions: Assumptions = { ...DEFAULT_ASSUMPTIONS };
    if (root.assumptions !== undefined) {
      const a = asObject(root.assumptions, 'assumptions');
      assumptions = {
        ascentSpeedMps: readNumber(a, 'ascentSpeedMps', 'assumptions'),
        descentSpeedMps: readNumber(a, 'descentSpeedMps', 'assumptions'),
        waypointPauseS: readNumber(a, 'waypointPauseS', 'assumptions'),
        usableFlightTimeS: readNumber(a, 'usableFlightTimeS', 'assumptions'),
        maxDistanceFromHomeM: readNumber(a, 'maxDistanceFromHomeM', 'assumptions'),
      };
    }

    let home: LatLng | null = null;
    if (root.home !== null && root.home !== undefined) {
      if (!isValidLatLng(root.home)) throw new FileError('Het startpunt ("home") heeft geen geldige GPS-coördinaten.');
      home = { lat: root.home.lat, lng: root.home.lng };
    }

    const boundary = readPoints(root.boundary, 'boundary').map((p) => ({ id: makeId(), ...p }));
    const rawRoute = root.routePoints === undefined ? [] : root.routePoints;
    const routeLatLng = readPoints(rawRoute, 'routePoints');
    const routePoints = routeLatLng.map((p, i) => {
      const capture = (rawRoute as Record<string, unknown>[])[i].capture;
      return { id: makeId(), ...p, capture: typeof capture === 'boolean' ? capture : true };
    });

    const name = typeof root.name === 'string' && root.name.trim() !== '' ? root.name : 'Geladen route';
    return { ok: true, plan: { name, mode, home, boundary, routePoints, settings, assumptions } };
  } catch (e) {
    if (e instanceof FileError) return { ok: false, error: e.message };
    throw e;
  }
}
