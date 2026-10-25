import { overlapFraction, type Footprint } from './camera';
import { haversineM, polygonAreaM2 } from './geo';
import type { Timeline } from './timeline';
import type { PhotoPoint, Plan, PlannedRoute } from './types';

export interface Estimate {
  /** Distance flown while taking photos (m). */
  photoDistanceM: number;
  /** Route distance without photos, such as transits between flight lines (m). */
  transitDistanceM: number;
  /** From the take-off point to the first waypoint and back from the last (m). */
  homeDistanceM: number;
  totalDistanceM: number;
  climbS: number;
  descentS: number;
  flyS: number;
  pauseS: number;
  totalS: number;
  photoCount: number;
  /** Distance between two photos along a line (m). */
  photoSpacingM: number;
  waypointCount: number;
  /** Share of the usable battery time (1 = 100 %). */
  batteryFraction: number;
  /** Area inside the field boundary (m²), null without a usable boundary. */
  fieldAreaM2: number | null;
  /** Farthest distance between a waypoint and the take-off point (m), null without take-off point. */
  maxDistanceFromHomeM: number | null;
  sideOverlap: number | null;
  frontOverlap: number | null;
}

export function estimatePlan(
  plan: Plan,
  route: PlannedRoute,
  photos: PhotoPoint[],
  timeline: Timeline,
  footprint: Footprint | null,
): Estimate {
  let photoDistanceM = 0;
  let transitDistanceM = 0;
  let homeDistanceM = 0;
  let climbS = 0;
  let descentS = 0;
  let flyS = 0;
  let pauseS = 0;
  for (const seg of timeline.segments) {
    const dur = seg.t1 - seg.t0;
    if (seg.phase === 'climb') climbS += dur;
    else if (seg.phase === 'descend') descentS += dur;
    else if (seg.phase === 'pause') pauseS += dur;
    else {
      flyS += dur;
      const d = haversineM(seg.from, seg.to);
      if (seg.legIndex === null) homeDistanceM += d;
      else if (seg.capture) photoDistanceM += d;
      else transitDistanceM += d;
    }
  }

  const photoSpacingM = plan.settings.speedMps * plan.settings.photoIntervalS;
  const fieldAreaM2 = plan.boundary.length >= 3 ? polygonAreaM2(plan.boundary) : null;
  const maxDistanceFromHomeM = plan.home
    ? route.waypoints.reduce((m, p) => Math.max(m, haversineM(plan.home!, p)), 0)
    : null;

  return {
    photoDistanceM,
    transitDistanceM,
    homeDistanceM,
    totalDistanceM: photoDistanceM + transitDistanceM + homeDistanceM,
    climbS,
    descentS,
    flyS,
    pauseS,
    totalS: timeline.totalS,
    photoCount: photos.length,
    photoSpacingM,
    waypointCount: route.waypoints.length,
    batteryFraction: plan.assumptions.usableFlightTimeS > 0 ? timeline.totalS / plan.assumptions.usableFlightTimeS : 0,
    fieldAreaM2,
    maxDistanceFromHomeM,
    sideOverlap:
      footprint && plan.mode === 'field' && plan.settings.lineSpacingM > 0
        ? overlapFraction(footprint.widthM, plan.settings.lineSpacingM)
        : null,
    frontOverlap: footprint && photoSpacingM > 0 ? overlapFraction(footprint.lengthM, photoSpacingM) : null,
  };
}
