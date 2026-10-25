import type { Assumptions, FlightSettings, Plan } from './types';

export const DEFAULT_SETTINGS: FlightSettings = {
  altitudeM: 30,
  speedMps: 4,
  lineSpacingM: 20,
  photoIntervalS: 3,
  lineAngleDeg: null,
  edgeMarginM: 5,
};

export const DEFAULT_ASSUMPTIONS: Assumptions = {
  // Position-mode climb and a slower-than-maximum descent (spec: 2 m/s and 1.8 m/s).
  ascentSpeedMps: 2,
  descentSpeedMps: 1.5,
  waypointPauseS: 3,
  // Two thirds of the 30 min spec: leaves a reserve for wind, cold and the return.
  usableFlightTimeS: 20 * 60,
  maxDistanceFromHomeM: 500,
};

export function createEmptyPlan(): Plan {
  return {
    name: 'Nieuwe route',
    mode: 'field',
    home: null,
    routePoints: [],
    boundary: [],
    settings: { ...DEFAULT_SETTINGS },
    assumptions: { ...DEFAULT_ASSUMPTIONS },
  };
}

let counter = 0;

/** Short unique id for points (only needs to be unique within one browser session). */
export function makeId(): string {
  counter += 1;
  return `p${Date.now().toString(36)}${counter.toString(36)}`;
}
