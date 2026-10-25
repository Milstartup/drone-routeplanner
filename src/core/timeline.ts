// Time model of the flight, used by the estimate and by the simulation.
// Assumptions: vertical climb at the take-off point, constant horizontal speed, a fixed
// pause at every waypoint (braking, turning, accelerating), return to the take-off point
// and vertical descent. No wind, no acceleration curves.
import { bearingDeg, haversineM, interpolate } from './geo';
import type { Assumptions, FlightSettings, LatLng, PhotoPoint, PlannedRoute } from './types';

export type Phase = 'climb' | 'fly' | 'pause' | 'descend';

export interface TimelineSegment {
  phase: Phase;
  t0: number;
  t1: number;
  from: LatLng;
  to: LatLng;
  alt0: number;
  alt1: number;
  /** Photos are planned while flying this segment. */
  capture: boolean;
  /** Route leg this segment flies, or null for climb/descent/pause and the flights to and from home. */
  legIndex: number | null;
  headingDeg: number;
}

export interface Timeline {
  segments: TimelineSegment[];
  totalS: number;
  /** Time at which each planned photo is taken (same order as the photos). */
  photoTimesS: number[];
}

export interface TimelineInput {
  route: PlannedRoute;
  photos: PhotoPoint[];
  home: LatLng | null;
  settings: FlightSettings;
  assumptions: Assumptions;
}

export function buildTimeline({ route, photos, home, settings, assumptions }: TimelineInput): Timeline {
  const wps = route.waypoints;
  const v = settings.speedMps;
  const alt = settings.altitudeM;
  if (wps.length === 0 || !(v > 0) || !(alt > 0)) return { segments: [], totalS: 0, photoTimesS: [] };

  const segments: TimelineSegment[] = [];
  let t = 0;
  let heading = wps.length > 1 ? bearingDeg(wps[0], wps[1]) : 0;
  const pause = Math.max(0, assumptions.waypointPauseS || 0);

  const addFly = (from: LatLng, to: LatLng, capture: boolean, legIndex: number | null) => {
    const d = haversineM(from, to);
    if (d > 0.01) heading = bearingDeg(from, to);
    segments.push({ phase: 'fly', t0: t, t1: t + d / v, from, to, alt0: alt, alt1: alt, capture, legIndex, headingDeg: heading });
    t += d / v;
  };
  const addStill = (phase: Phase, at: LatLng, duration: number, alt0: number, alt1: number) => {
    segments.push({ phase, t0: t, t1: t + duration, from: at, to: at, alt0, alt1, capture: false, legIndex: null, headingDeg: heading });
    t += duration;
  };

  if (home) {
    if (haversineM(home, wps[0]) > 0.5) heading = bearingDeg(home, wps[0]);
    addStill('climb', home, alt / assumptions.ascentSpeedMps, 0, alt);
    addFly(home, wps[0], false, null);
    if (pause > 0) addStill('pause', wps[0], pause, alt, alt);
  }

  const legStart: number[] = [];
  const legEnd: number[] = [];
  route.legs.forEach((leg, i) => {
    legStart[i] = t;
    addFly(leg.from, leg.to, leg.capture, i);
    legEnd[i] = t;
    const last = i === route.legs.length - 1;
    if (pause > 0 && (!last || home)) addStill('pause', leg.to, pause, alt, alt);
  });

  if (home) {
    addFly(wps[wps.length - 1], home, false, null);
    addStill('descend', home, alt / assumptions.descentSpeedMps, alt, 0);
  }

  const photoTimesS = photos.map((p) => {
    const t0 = legStart[p.legIndex] ?? 0;
    const t1 = legEnd[p.legIndex] ?? t0;
    return t0 + p.legFraction * (t1 - t0);
  });
  return { segments, totalS: t, photoTimesS };
}

export interface DroneState {
  position: LatLng;
  altitudeM: number;
  headingDeg: number;
  phase: Phase | 'done';
  capture: boolean;
}

/** Simulated drone state at time t (seconds since the start). */
export function stateAt(timeline: Timeline, t: number): DroneState | null {
  const segs = timeline.segments;
  if (segs.length === 0) return null;
  if (t >= timeline.totalS) {
    const last = segs[segs.length - 1];
    return { position: last.to, altitudeM: last.alt1, headingDeg: last.headingDeg, phase: 'done', capture: false };
  }
  // First segment that ends after t.
  let lo = 0;
  let hi = segs.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (segs[mid].t1 > t) hi = mid;
    else lo = mid + 1;
  }
  const seg = segs[lo];
  const dur = seg.t1 - seg.t0;
  const f = dur > 0 ? Math.min(1, Math.max(0, (t - seg.t0) / dur)) : 1;
  return {
    position: interpolate(seg.from, seg.to, f),
    altitudeM: seg.alt0 + (seg.alt1 - seg.alt0) * f,
    headingDeg: seg.headingDeg,
    phase: seg.phase,
    capture: seg.capture,
  };
}

/** Number of photos taken up to and including time t. */
export function photosTakenAt(timeline: Timeline, t: number): number {
  const times = timeline.photoTimesS;
  let lo = 0;
  let hi = times.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (times[mid] <= t) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}
