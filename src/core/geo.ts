// Geometry helpers. Distances on the earth use haversine; shape operations use a local flat
// projection in metres, which is accurate enough for a single field (a few km at most).
import type { LatLng, XY } from './types';

export const EARTH_RADIUS_M = 6371008.8;
export const DEG = Math.PI / 180;

export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = (b.lat - a.lat) * DEG;
  const dLng = (b.lng - a.lng) * DEG;
  const s =
    Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * DEG) * Math.cos(b.lat * DEG) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(s)));
}

export function pathLengthM(points: LatLng[]): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += haversineM(points[i - 1], points[i]);
  return total;
}

/** Compass bearing from a to b in degrees (0 = north, 90 = east). */
export function bearingDeg(a: LatLng, b: LatLng): number {
  const phi1 = a.lat * DEG;
  const phi2 = b.lat * DEG;
  const dLng = (b.lng - a.lng) * DEG;
  const y = Math.sin(dLng) * Math.cos(phi2);
  const x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLng);
  return (Math.atan2(y, x) / DEG + 360) % 360;
}

/** Straight interpolation in degrees; fine for the short legs inside one field. */
export function interpolate(a: LatLng, b: LatLng, f: number): LatLng {
  return { lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f };
}

export function isValidLatLng(p: unknown): p is LatLng {
  if (typeof p !== 'object' || p === null) return false;
  const { lat, lng } = p as Record<string, unknown>;
  return (
    typeof lat === 'number' &&
    typeof lng === 'number' &&
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

export interface LocalProjection {
  origin: LatLng;
  toXY(p: LatLng): XY;
  toLatLng(p: XY): LatLng;
}

/** Equirectangular projection around an origin; error stays far below 0.1 % within a few km. */
export function localProjection(origin: LatLng): LocalProjection {
  const kLat = EARTH_RADIUS_M * DEG;
  const kLng = kLat * Math.cos(origin.lat * DEG);
  return {
    origin,
    toXY: (p) => ({ x: (p.lng - origin.lng) * kLng, y: (p.lat - origin.lat) * kLat }),
    toLatLng: (p) => ({ lat: origin.lat + p.y / kLat, lng: origin.lng + p.x / kLng }),
  };
}

/** Average of the vertices; used as projection origin. */
export function centroid(points: LatLng[]): LatLng {
  let lat = 0;
  let lng = 0;
  for (const p of points) {
    lat += p.lat;
    lng += p.lng;
  }
  return { lat: lat / points.length, lng: lng / points.length };
}

export function polygonAreaXY(poly: XY[]): number {
  let twice = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return Math.abs(twice) / 2;
}

export function polygonAreaM2(points: LatLng[]): number {
  if (points.length < 3) return 0;
  const proj = localProjection(centroid(points));
  return polygonAreaXY(points.map(proj.toXY));
}

function cross(o: XY, a: XY, b: XY): number {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

function onSegment(a: XY, b: XY, p: XY): boolean {
  return (
    Math.min(a.x, b.x) - 1e-9 <= p.x &&
    p.x <= Math.max(a.x, b.x) + 1e-9 &&
    Math.min(a.y, b.y) - 1e-9 <= p.y &&
    p.y <= Math.max(a.y, b.y) + 1e-9
  );
}

/** True when segments p1-p2 and p3-p4 cross or touch. */
export function segmentsIntersect(p1: XY, p2: XY, p3: XY, p4: XY): boolean {
  const d1 = cross(p3, p4, p1);
  const d2 = cross(p3, p4, p2);
  const d3 = cross(p1, p2, p3);
  const d4 = cross(p1, p2, p4);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  const eps = 1e-9;
  return (
    (Math.abs(d1) < eps && onSegment(p3, p4, p1)) ||
    (Math.abs(d2) < eps && onSegment(p3, p4, p2)) ||
    (Math.abs(d3) < eps && onSegment(p1, p2, p3)) ||
    (Math.abs(d4) < eps && onSegment(p1, p2, p4))
  );
}

/** True only when the segments cross in their interiors (touching does not count). */
function properlyCross(p1: XY, p2: XY, p3: XY, p4: XY): boolean {
  const eps = 1e-9;
  const d1 = cross(p3, p4, p1);
  const d2 = cross(p3, p4, p2);
  const d3 = cross(p1, p2, p3);
  const d4 = cross(p1, p2, p4);
  return d1 * d2 < -eps && d3 * d4 < -eps;
}

/**
 * Returns the indexes [i, j] of the first two non-neighbouring edges that intersect
 * (edge i runs from point i to point i + 1), or null when the polygon is simple.
 */
export function findSelfIntersection(poly: XY[]): [number, number] | null {
  const n = poly.length;
  if (n < 4) return null;
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const neighbours = j === i + 1 || (i === 0 && j === n - 1);
      if (neighbours) continue;
      if (segmentsIntersect(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n])) return [i, j];
    }
  }
  return null;
}

export function pointInPolygon(p: XY, poly: XY[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i];
    const b = poly[j];
    if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

export function distancePointToSegment(p: XY, a: XY, b: XY): number {
  const ex = b.x - a.x;
  const ey = b.y - a.y;
  const len2 = ex * ex + ey * ey;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * ex + (p.y - a.y) * ey) / len2));
  return Math.hypot(p.x - (a.x + t * ex), p.y - (a.y + t * ey));
}

export function distanceToPolygonEdges(p: XY, poly: XY[]): number {
  let best = Infinity;
  for (let i = 0; i < poly.length; i++) {
    best = Math.min(best, distancePointToSegment(p, poly[i], poly[(i + 1) % poly.length]));
  }
  return best;
}

/** True when segment a-b stays inside the polygon (its ends may touch the boundary). */
export function segmentInsidePolygon(a: XY, b: XY, poly: XY[]): boolean {
  for (let i = 0; i < poly.length; i++) {
    if (properlyCross(a, b, poly[i], poly[(i + 1) % poly.length])) return false;
  }
  for (const f of [0.25, 0.5, 0.75]) {
    const p = { x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f };
    if (!pointInPolygon(p, poly) && distanceToPolygonEdges(p, poly) > 1e-6) return false;
  }
  return true;
}
