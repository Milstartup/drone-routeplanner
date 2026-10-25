// Checks for invalid field boundaries, routes and settings. Errors block the simulation and
// the export; warnings are shown but do not block anything.
import type { Footprint } from './camera';
import type { Estimate } from './estimate';
import {
  centroid,
  findSelfIntersection,
  haversineM,
  isValidLatLng,
  localProjection,
  pointInPolygon,
  polygonAreaXY,
} from './geo';
import { EU_MAX_ALTITUDE_M, MAVIC_MINI } from './mavicMini';
import { MAX_PHOTOS } from './photos';
import { formatDistance, formatDuration, formatNumber, formatArea } from './format';
import type { Plan, PlannedRoute } from './types';

export type IssueLevel = 'error' | 'warning';
export type IssueArea = 'settings' | 'assumptions' | 'boundary' | 'route' | 'home' | 'estimate';

export interface Issue {
  level: IssueLevel;
  code: string;
  area: IssueArea;
  message: string;
}

export const LIMITS = {
  minAltitudeM: 5,
  lowAltitudeWarningM: 15,
  maxAltitudeM: EU_MAX_ALTITUDE_M,
  // The SDK only controls the Mavic Mini in P mode (DJI hardware table), where 8 m/s is the maximum.
  maxSpeedMps: MAVIC_MINI.maxSpeedMps.position,
  speedWarningMps: 6,
  minLineSpacingM: 2,
  minPhotoIntervalS: 0.5,
  photoIntervalWarningS: 2,
  minBoundaryAreaM2: 100,
  largeFieldWarningM2: 50 * 10000,
  maxFieldExtentM: 5000,
  duplicatePointM: 0.5,
  manyPhotosWarning: 3000,
} as const;

interface Derived {
  route: PlannedRoute;
  estimate: Estimate;
  footprint: Footprint | null;
}

function isNum(n: unknown): n is number {
  return typeof n === 'number' && Number.isFinite(n);
}

export function validatePlan(plan: Plan, { route, estimate, footprint }: Derived): Issue[] {
  const issues: Issue[] = [];
  const add = (level: IssueLevel, area: IssueArea, code: string, message: string) =>
    issues.push({ level, area, code, message });
  const s = plan.settings;

  // Settings
  if (!isNum(s.altitudeM)) add('error', 'settings', 'altitude-invalid', 'Vlieghoogte: vul een getal in.');
  else if (s.altitudeM < LIMITS.minAltitudeM)
    add('error', 'settings', 'altitude-low', `Vlieghoogte moet minstens ${LIMITS.minAltitudeM} m zijn.`);
  else if (s.altitudeM > LIMITS.maxAltitudeM)
    add('error', 'settings', 'altitude-high', `Vlieghoogte is hoger dan ${LIMITS.maxAltitudeM} m, de grens in de open categorie van de EU-dronewetgeving.`);
  else if (s.altitudeM < LIMITS.lowAltitudeWarningM)
    add('warning', 'settings', 'altitude-lowish', `Lage vlieghoogte (onder ${LIMITS.lowAltitudeWarningM} m): let op bomen, hekken, masten en lijnen rond het veld.`);

  if (!isNum(s.speedMps)) add('error', 'settings', 'speed-invalid', 'Snelheid: vul een getal in.');
  else if (s.speedMps <= 0) add('error', 'settings', 'speed-invalid', 'Snelheid moet groter dan 0 zijn.');
  else if (s.speedMps > LIMITS.maxSpeedMps)
    add('error', 'settings', 'speed-high', `Snelheid is hoger dan ${LIMITS.maxSpeedMps} m/s. Een app bestuurt de Mavic Mini alleen in de P-stand, en daarin is ${LIMITS.maxSpeedMps} m/s het maximum.`);
  else if (s.speedMps > LIMITS.speedWarningMps)
    add('warning', 'settings', 'speed-fast', `Snelheid boven ${LIMITS.speedWarningMps} m/s: weinig marge bij tegenwind (de Mavic Mini kan wind tot 8 m/s aan) en meer kans op onscherpe foto's.`);

  if (plan.mode === 'field') {
    if (!isNum(s.lineSpacingM)) add('error', 'settings', 'spacing-invalid', 'Baanafstand: vul een getal in.');
    else if (s.lineSpacingM < LIMITS.minLineSpacingM)
      add('error', 'settings', 'spacing-small', `Baanafstand moet minstens ${LIMITS.minLineSpacingM} m zijn.`);
    if (!isNum(s.edgeMarginM) || s.edgeMarginM < 0)
      add('error', 'settings', 'margin-invalid', 'Randmarge: vul een getal van 0 of meer in.');
    if (s.lineAngleDeg !== null && !isNum(s.lineAngleDeg))
      add('error', 'settings', 'angle-invalid', 'Baanrichting: vul een getal in (0–179°) of kies automatisch.');
  }

  if (!isNum(s.photoIntervalS)) add('error', 'settings', 'interval-invalid', 'Foto-interval: vul een getal in.');
  else if (s.photoIntervalS < LIMITS.minPhotoIntervalS)
    add('error', 'settings', 'interval-small', `Foto-interval moet minstens ${formatNumber(LIMITS.minPhotoIntervalS, 1)} s zijn.`);
  else if (s.photoIntervalS < LIMITS.photoIntervalWarningS)
    add('warning', 'settings', 'interval-short', `Foto-interval korter dan ${LIMITS.photoIntervalWarningS} s: de kortste intervalstand van de Mavic Mini is 2 s. Kortere tussenpozen zijn niet getest.`);

  if (footprint && isNum(s.lineSpacingM) && plan.mode === 'field' && s.lineSpacingM > footprint.widthM) {
    add('warning', 'settings', 'side-gap', `Baanafstand (${formatNumber(s.lineSpacingM)} m) is groter dan de fotobreedte op ${formatNumber(s.altitudeM)} m hoogte (${formatNumber(footprint.widthM)} m): er blijven stroken zonder foto.`);
  }
  if (footprint && estimate.photoSpacingM > footprint.lengthM) {
    add('warning', 'settings', 'front-gap', `Afstand tussen foto's (${formatNumber(estimate.photoSpacingM, 1)} m) is groter dan de fotolengte (${formatNumber(footprint.lengthM)} m): er vallen gaten tussen opeenvolgende foto's.`);
  }

  // Assumptions
  const a = plan.assumptions;
  const assumptionFields: [number, string][] = [
    [a.ascentSpeedMps, 'stijgsnelheid'],
    [a.descentSpeedMps, 'daalsnelheid'],
    [a.usableFlightTimeS, 'bruikbare vliegtijd'],
    [a.maxDistanceFromHomeM, 'maximale afstand tot startpunt'],
  ];
  for (const [value, label] of assumptionFields) {
    if (!isNum(value) || value <= 0) add('error', 'assumptions', 'assumption-invalid', `Aanname "${label}" moet een getal groter dan 0 zijn.`);
  }
  if (!isNum(a.waypointPauseS) || a.waypointPauseS < 0)
    add('error', 'assumptions', 'assumption-invalid', 'Aanname "pauze per routepunt" moet 0 of meer zijn.');

  // Coordinates (matters for loaded files)
  const allPoints = [...plan.boundary, ...plan.routePoints, ...(plan.home ? [plan.home] : [])];
  if (allPoints.some((p) => !isValidLatLng(p))) {
    add('error', 'route', 'coord-invalid', 'Een of meer punten hebben ongeldige GPS-coördinaten.');
    return issues;
  }

  // Field boundary
  const boundaryOk = validateBoundary(plan, plan.mode === 'field', add);
  if (plan.mode === 'field' && boundaryOk) {
    if (route.lineCount === 0 && issues.every((i) => i.area !== 'settings' || i.level !== 'error')) {
      add('error', 'boundary', 'no-lines', 'Er passen geen vliegbanen in het veld met deze baanafstand en randmarge. Verklein de randmarge of de baanafstand.');
    }
    if (route.transitsOutside > 0) {
      add('warning', 'boundary', 'transit-outside', `${route.transitsOutside} overgang(en) tussen vliegbanen lopen buiten de veldgrens (onregelmatige vorm). Controleer die plekken op obstakels of kies een andere baanrichting.`);
    }
  }

  // Manual route
  if (plan.mode === 'route') {
    const pts = plan.routePoints;
    if (pts.length < 2) add('error', 'route', 'route-too-few', 'Klik minstens 2 routepunten op de kaart.');
    for (let i = 1; i < pts.length; i++) {
      if (haversineM(pts[i - 1], pts[i]) < LIMITS.duplicatePointM) {
        add('warning', 'route', 'route-duplicate', `Routepunt ${i} en ${i + 1} liggen op dezelfde plek.`);
      }
    }
    if (pts.length >= 2 && pts.slice(0, -1).every((p) => !p.capture)) {
      add('warning', 'route', 'route-no-photos', "Op geen enkel stuk van de route staan foto's gepland.");
    }
    if (boundaryOk && plan.boundary.length >= 3) {
      const proj = localProjection(centroid(plan.boundary));
      const poly = plan.boundary.map(proj.toXY);
      const outside = pts.map((p, i) => (pointInPolygon(proj.toXY(p), poly) ? -1 : i + 1)).filter((i) => i > 0);
      if (outside.length > 0) {
        add('warning', 'route', 'route-outside-field', `Routepunt ${outside.join(', ')} ligt buiten de veldgrens.`);
      }
    }
  }

  // Take-off point and distances
  if (!plan.home) {
    add('warning', 'home', 'home-missing', 'Geen startpunt geplaatst: opstijgen, heen- en terugvliegen en landen tellen niet mee in de schatting.');
  } else if (estimate.maxDistanceFromHomeM !== null && estimate.maxDistanceFromHomeM > a.maxDistanceFromHomeM) {
    add('warning', 'home', 'home-far', `Het verste routepunt ligt ${formatDistance(estimate.maxDistanceFromHomeM)} van het startpunt. Je moet de drone met eigen ogen kunnen zien (aanname: tot ${formatDistance(a.maxDistanceFromHomeM)}).`);
  }

  // Estimate
  if (estimate.totalS > 0 && a.usableFlightTimeS > 0 && estimate.totalS > a.usableFlightTimeS) {
    add('warning', 'estimate', 'battery', `Geschatte vliegtijd (${formatDuration(estimate.totalS)}) is langer dan de bruikbare accutijd (${formatDuration(a.usableFlightTimeS)}). Verdeel het veld over meerdere vluchten of vergroot snelheid of baanafstand.`);
  }
  if (estimate.photoCount >= MAX_PHOTOS) {
    add('error', 'estimate', 'photos-max', `Meer dan ${formatNumber(MAX_PHOTOS)} foto's: vergroot het foto-interval.`);
  } else if (estimate.photoCount > LIMITS.manyPhotosWarning) {
    add('warning', 'estimate', 'photos-many', `${formatNumber(estimate.photoCount)} foto's: controleer of de geheugenkaart groot genoeg is.`);
  }

  return issues;
}

/** Returns true when the boundary has a usable shape (only reports issues when `report` is set). */
function validateBoundary(
  plan: Plan,
  report: boolean,
  add: (level: IssueLevel, area: IssueArea, code: string, message: string) => void,
): boolean {
  const b = plan.boundary;
  const say = (level: IssueLevel, code: string, message: string) => {
    if (report) add(level, 'boundary', code, message);
  };
  if (b.length < 3) {
    say('error', 'boundary-too-few', 'Teken minstens 3 punten voor de veldgrens.');
    return false;
  }
  let ok = true;
  for (let i = 0; i < b.length; i++) {
    const j = (i + 1) % b.length;
    if (haversineM(b[i], b[j]) < LIMITS.duplicatePointM) {
      say('error', 'boundary-duplicate', `Punt ${i + 1} en ${j + 1} van de veldgrens liggen op dezelfde plek. Verwijder er één.`);
      ok = false;
    }
  }
  const proj = localProjection(centroid(b));
  const poly = b.map(proj.toXY);
  const cross = findSelfIntersection(poly);
  if (cross) {
    const [i, j] = cross;
    say('error', 'boundary-self-intersect', `De veldgrens kruist zichzelf (lijn ${i + 1}–${(i + 1) % b.length + 1} en lijn ${j + 1}–${(j + 1) % b.length + 1}). Versleep of verwijder een punt.`);
    return false;
  }
  const xs = poly.map((p) => p.x);
  const ys = poly.map((p) => p.y);
  const extent = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys));
  if (extent > LIMITS.maxFieldExtentM) {
    say('error', 'boundary-extent', `Het veld is ${formatDistance(extent)} breed. Deze planner is bedoeld voor velden tot ${formatDistance(LIMITS.maxFieldExtentM)}.`);
    ok = false;
  }
  const area = polygonAreaXY(poly);
  if (area < LIMITS.minBoundaryAreaM2) {
    say('error', 'boundary-small', `Het veld is kleiner dan ${formatArea(LIMITS.minBoundaryAreaM2)}.`);
    ok = false;
  } else if (area > LIMITS.largeFieldWarningM2) {
    say('warning', 'boundary-large', `Groot veld (${formatArea(area)}): reken op meerdere vluchten en accu's.`);
  }
  return ok;
}
