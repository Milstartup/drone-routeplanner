// Generates parallel flight lines ("lawnmower" pattern) inside a field boundary.
//
// Steps: project the boundary to metres, rotate it so the flight lines are horizontal,
// cut it with horizontal scan lines, remove the parts closer than the edge margin to any
// boundary edge, then link the pieces into one path (nearest next line end first).
// Works for concave fields too; transits between pieces that leave the field are counted.
import { DEG, centroid, localProjection, segmentInsidePolygon } from './geo';
import type { LatLng, RouteLeg, XY } from './types';

export interface CoverageOptions {
  lineSpacingM: number;
  /** Compass bearing of the lines; null = parallel to the longest boundary edge. */
  lineAngleDeg: number | null;
  edgeMarginM: number;
  /** Start at the line end nearest to this point (usually the take-off point). */
  start?: LatLng | null;
}

export interface CoverageResult {
  waypoints: LatLng[];
  legs: RouteLeg[];
  /** Number of straight photo lines (a concave field can have several per scan line). */
  lineCount: number;
  angleDeg: number;
  transitsOutside: number;
}

/** Pieces shorter than this are dropped. */
export const MIN_LINE_LENGTH_M = 1;
const MAX_SCAN_LINES = 2000;

type Interval = [number, number];

interface Piece {
  y: number;
  x0: number;
  x1: number;
}

/** Lines have no direction, so bearings are folded into [0, 180). */
export function normalizeLineAngle(deg: number): number {
  const d = deg % 180;
  return d < 0 ? d + 180 : d;
}

/** Bearing of the longest boundary edge. */
export function autoLineAngleDeg(poly: XY[]): number {
  let best = 0;
  let bestLen = -1;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const len = Math.hypot(b.x - a.x, b.y - a.y);
    if (len > bestLen) {
      bestLen = len;
      best = Math.atan2(b.x - a.x, b.y - a.y) / DEG;
    }
  }
  return normalizeLineAngle(best);
}

/** x-range where k * x + m lies in [lo, hi]. */
function linearRange(k: number, m: number, lo: number, hi: number): Interval | null {
  if (Math.abs(k) < 1e-12) return m >= lo && m <= hi ? [-Infinity, Infinity] : null;
  const a = (lo - m) / k;
  const b = (hi - m) / k;
  return a < b ? [a, b] : [b, a];
}

/** Part of the horizontal line at height y that is closer than d to segment a-b. */
function nearEdgeInterval(a: XY, b: XY, y: number, d: number): Interval | null {
  let lo = Infinity;
  let hi = -Infinity;
  for (const p of [a, b]) {
    const dy = y - p.y;
    if (Math.abs(dy) < d) {
      const h = Math.sqrt(d * d - dy * dy);
      lo = Math.min(lo, p.x - h);
      hi = Math.max(hi, p.x + h);
    }
  }
  const ex = b.x - a.x;
  const ey = b.y - a.y;
  const len = Math.hypot(ex, ey);
  if (len > 1e-9) {
    const ux = ex / len;
    const uy = ey / len;
    // Along the edge: 0..len. Across the edge: -d..d.
    const along = linearRange(ux, -a.x * ux + (y - a.y) * uy, 0, len);
    const across = linearRange(-uy, a.x * uy + (y - a.y) * ux, -d, d);
    if (along && across) {
      const r0 = Math.max(along[0], across[0]);
      const r1 = Math.min(along[1], across[1]);
      if (r0 < r1) {
        lo = Math.min(lo, r0);
        hi = Math.max(hi, r1);
      }
    }
  }
  return lo < hi ? [lo, hi] : null;
}

function mergeIntervals(list: Interval[]): Interval[] {
  const sorted = [...list].sort((p, q) => p[0] - q[0]);
  const out: Interval[] = [];
  for (const iv of sorted) {
    const last = out[out.length - 1];
    if (last && iv[0] <= last[1]) last[1] = Math.max(last[1], iv[1]);
    else out.push([iv[0], iv[1]]);
  }
  return out;
}

function subtractIntervals(from: Interval[], blocked: Interval[]): Interval[] {
  const out: Interval[] = [];
  for (const [a, b] of from) {
    let cur = a;
    for (const [c, d] of blocked) {
      if (d <= cur) continue;
      if (c >= b) break;
      if (c > cur) out.push([cur, c]);
      cur = Math.max(cur, d);
      if (cur >= b) break;
    }
    if (cur < b) out.push([cur, b]);
  }
  return out;
}

/** Inside parts of the horizontal line at height y, at least `margin` away from every edge. */
function lineIntervals(poly: XY[], y: number, margin: number): Interval[] {
  const xs: number[] = [];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
      xs.push(a.x + ((y - a.y) * (b.x - a.x)) / (b.y - a.y));
    }
  }
  xs.sort((p, q) => p - q);
  const inside: Interval[] = [];
  for (let i = 0; i + 1 < xs.length; i += 2) inside.push([xs[i], xs[i + 1]]);
  if (margin <= 0) return inside;

  const blocked: Interval[] = [];
  for (let i = 0; i < poly.length; i++) {
    const iv = nearEdgeInterval(poly[i], poly[(i + 1) % poly.length], y, margin);
    if (iv) blocked.push(iv);
  }
  return subtractIntervals(inside, mergeIntervals(blocked));
}

export function generateCoverage(boundary: LatLng[], options: CoverageOptions): CoverageResult {
  const spacing = options.lineSpacingM;
  const margin = Number.isFinite(options.edgeMarginM) ? Math.max(0, options.edgeMarginM) : 0;
  const empty = (angleDeg: number): CoverageResult => ({
    waypoints: [],
    legs: [],
    lineCount: 0,
    angleDeg,
    transitsOutside: 0,
  });
  if (boundary.length < 3) return empty(options.lineAngleDeg ?? 0);

  const proj = localProjection(centroid(boundary));
  const poly = boundary.map(proj.toXY);
  const angleDeg =
    options.lineAngleDeg == null || !Number.isFinite(options.lineAngleDeg)
      ? autoLineAngleDeg(poly)
      : normalizeLineAngle(options.lineAngleDeg);
  if (!(spacing > 0)) return empty(angleDeg);

  // Rotate so that the line direction (bearing) becomes the +x axis.
  const s = Math.sin(angleDeg * DEG);
  const c = Math.cos(angleDeg * DEG);
  const rotate = (p: XY): XY => ({ x: p.x * s + p.y * c, y: -p.x * c + p.y * s });
  const unrotate = (p: XY): XY => ({ x: p.x * s - p.y * c, y: p.x * c + p.y * s });
  const rp = poly.map(rotate);

  const ys = rp.map((p) => p.y);
  const inset = Math.max(margin, 0.01);
  const lo = Math.min(...ys) + inset;
  const hi = Math.max(...ys) - inset;
  const pieces: Piece[] = [];
  if (hi >= lo) {
    const n = Math.min(MAX_SCAN_LINES, Math.floor((hi - lo) / spacing + 1e-9) + 1);
    // Centre the lines in the band so both outer lines sit equally far from the edge.
    const first = lo + (hi - lo - (n - 1) * spacing) / 2;
    for (let k = 0; k < n; k++) {
      const y = first + k * spacing;
      for (const [x0, x1] of lineIntervals(rp, y, margin)) {
        if (x1 - x0 >= MIN_LINE_LENGTH_M) pieces.push({ y, x0, x1 });
      }
    }
  }
  if (pieces.length === 0) return empty(angleDeg);

  const ordered = orderPieces(pieces, options.start ? rotate(proj.toXY(options.start)) : null);

  const toLatLng = (p: XY): LatLng => proj.toLatLng(unrotate(p));
  const waypoints: LatLng[] = [];
  const legs: RouteLeg[] = [];
  let transitsOutside = 0;
  ordered.forEach((seg, i) => {
    const start = toLatLng(seg.start);
    const end = toLatLng(seg.end);
    if (i > 0) {
      const prev = ordered[i - 1].end;
      if (!segmentInsidePolygon(prev, seg.start, rp)) transitsOutside++;
      legs.push({ from: waypoints[waypoints.length - 1], to: start, capture: false });
    }
    waypoints.push(start);
    legs.push({ from: start, to: end, capture: true });
    waypoints.push(end);
  });
  return { waypoints, legs, lineCount: ordered.length, angleDeg, transitsOutside };
}

interface OrientedPiece {
  start: XY;
  end: XY;
}

/**
 * Starts on an outer line (the end nearest to `start`), then always flies to the nearest
 * free line end. For a convex field this gives the classic back-and-forth pattern.
 */
function orderPieces(pieces: Piece[], start: XY | null): OrientedPiece[] {
  const ends = (p: Piece): [XY, XY] => [
    { x: p.x0, y: p.y },
    { x: p.x1, y: p.y },
  ];
  const minY = Math.min(...pieces.map((p) => p.y));
  const maxY = Math.max(...pieces.map((p) => p.y));
  const outer = pieces
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => Math.abs(p.y - minY) < 1e-6 || Math.abs(p.y - maxY) < 1e-6);

  let firstIndex = outer[0].i;
  let firstReversed = false;
  if (start) {
    let best = Infinity;
    for (const { p, i } of outer) {
      const [a, b] = ends(p);
      const da = Math.hypot(a.x - start.x, a.y - start.y);
      const db = Math.hypot(b.x - start.x, b.y - start.y);
      if (da < best) {
        best = da;
        firstIndex = i;
        firstReversed = false;
      }
      if (db < best) {
        best = db;
        firstIndex = i;
        firstReversed = true;
      }
    }
  }

  const used = new Array<boolean>(pieces.length).fill(false);
  const result: OrientedPiece[] = [];
  const take = (i: number, reversed: boolean) => {
    used[i] = true;
    const [a, b] = ends(pieces[i]);
    result.push(reversed ? { start: b, end: a } : { start: a, end: b });
  };
  take(firstIndex, firstReversed);
  while (result.length < pieces.length) {
    const pos = result[result.length - 1].end;
    let bestI = -1;
    let bestReversed = false;
    let best = Infinity;
    for (let i = 0; i < pieces.length; i++) {
      if (used[i]) continue;
      const [a, b] = ends(pieces[i]);
      const da = Math.hypot(a.x - pos.x, a.y - pos.y);
      const db = Math.hypot(b.x - pos.x, b.y - pos.y);
      if (da < best) {
        best = da;
        bestI = i;
        bestReversed = false;
      }
      if (db < best) {
        best = db;
        bestI = i;
        bestReversed = true;
      }
    }
    take(bestI, bestReversed);
  }
  return result;
}
