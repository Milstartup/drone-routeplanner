import { generateCoverage } from './coverage';
import { centroid, findSelfIntersection, localProjection } from './geo';
import type { Plan, PlannedRoute } from './types';

/** The route the drone would fly for this plan (no photos, no timing). */
export function buildRoute(plan: Plan): PlannedRoute {
  if (plan.mode === 'field') {
    const boundary = plan.boundary;
    if (boundary.length < 3 || boundaryCrossesItself(plan)) {
      return { waypoints: [], legs: [], lineCount: 0, lineAngleDeg: plan.settings.lineAngleDeg, transitsOutside: 0 };
    }
    const cov = generateCoverage(boundary, { ...plan.settings, start: plan.home });
    return {
      waypoints: cov.waypoints,
      legs: cov.legs,
      lineCount: cov.lineCount,
      lineAngleDeg: cov.angleDeg,
      transitsOutside: cov.transitsOutside,
    };
  }

  const pts = plan.routePoints;
  return {
    waypoints: pts.map(({ lat, lng }) => ({ lat, lng })),
    legs: pts.slice(0, -1).map((p, i) => ({
      from: { lat: p.lat, lng: p.lng },
      to: { lat: pts[i + 1].lat, lng: pts[i + 1].lng },
      capture: p.capture,
    })),
    lineCount: 0,
    lineAngleDeg: null,
    transitsOutside: 0,
  };
}

export function boundaryCrossesItself(plan: Plan): boolean {
  if (plan.boundary.length < 4) return false;
  const proj = localProjection(centroid(plan.boundary));
  return findSelfIntersection(plan.boundary.map(proj.toXY)) !== null;
}
