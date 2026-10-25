// Helpers for the unit tests: build fields in metres around a fixed point in Flevoland.
import { createEmptyPlan, makeId } from './defaults';
import { localProjection } from './geo';
import type { LatLng, Plan } from './types';

export const ORIGIN: LatLng = { lat: 52.5, lng: 5.5 };
export const originProjection = localProjection(ORIGIN);

export function fromMeters(points: [number, number][]): LatLng[] {
  return points.map(([x, y]) => originProjection.toLatLng({ x, y }));
}

export function rectangle(width: number, height: number): LatLng[] {
  return fromMeters([
    [0, 0],
    [width, 0],
    [width, height],
    [0, height],
  ]);
}

export function fieldPlan(boundary: LatLng[], changes: Partial<Plan> = {}): Plan {
  const plan = createEmptyPlan();
  return {
    ...plan,
    mode: 'field',
    boundary: boundary.map((p) => ({ id: makeId(), ...p })),
    ...changes,
    settings: { ...plan.settings, ...changes.settings },
    assumptions: { ...plan.assumptions, ...changes.assumptions },
  };
}

export function routePlan(points: LatLng[], changes: Partial<Plan> = {}): Plan {
  const plan = createEmptyPlan();
  return {
    ...plan,
    mode: 'route',
    routePoints: points.map((p) => ({ id: makeId(), ...p, capture: true })),
    ...changes,
    settings: { ...plan.settings, ...changes.settings },
    assumptions: { ...plan.assumptions, ...changes.assumptions },
  };
}
