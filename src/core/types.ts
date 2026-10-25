// Shared data types for the route planner core.
// Everything in src/core is plain TypeScript: no React, no map library and no drone SDK.

/** WGS84 coordinate in decimal degrees (EPSG:4326). */
export interface LatLng {
  lat: number;
  lng: number;
}

/** Local flat coordinate in metres (x = east, y = north). */
export interface XY {
  x: number;
  y: number;
}

export interface BoundaryPoint extends LatLng {
  id: string;
}

export interface RoutePoint extends LatLng {
  id: string;
  /** Take photos on the leg from this point to the next one. */
  capture: boolean;
}

/** 'route' = waypoints clicked by the user, 'field' = boundary + generated parallel lines. */
export type PlanMode = 'route' | 'field';

export interface FlightSettings {
  /** Height above the take-off point in metres. */
  altitudeM: number;
  /** Horizontal speed in m/s. */
  speedMps: number;
  /** Distance between neighbouring flight lines in metres (field mode). */
  lineSpacingM: number;
  /** Seconds between photos while flying at constant speed. */
  photoIntervalS: number;
  /** Compass bearing of the flight lines in degrees, or null for automatic (longest edge). */
  lineAngleDeg: number | null;
  /** Minimum distance between flight lines and the field boundary in metres. */
  edgeMarginM: number;
}

/** Planning assumptions the user may tune. Shown in the UI and saved in the plan file. */
export interface Assumptions {
  ascentSpeedMps: number;
  descentSpeedMps: number;
  /** Time lost per waypoint for braking, turning and accelerating. */
  waypointPauseS: number;
  /** Flight time you are willing to use from one battery, including reserve. */
  usableFlightTimeS: number;
  /** Maximum distance from the take-off point you can still see the drone (VLOS). */
  maxDistanceFromHomeM: number;
}

export interface Plan {
  name: string;
  mode: PlanMode;
  /** Take-off and landing point. Optional while drawing. */
  home: LatLng | null;
  routePoints: RoutePoint[];
  boundary: BoundaryPoint[];
  settings: FlightSettings;
  assumptions: Assumptions;
}

export interface RouteLeg {
  from: LatLng;
  to: LatLng;
  /** Photos are planned on this leg. */
  capture: boolean;
}

/** The route the drone would fly, independent of how it was made. */
export interface PlannedRoute {
  waypoints: LatLng[];
  /** legs[i] goes from waypoints[i] to waypoints[i + 1]. */
  legs: RouteLeg[];
  /** Number of generated flight lines (field mode), 0 in route mode. */
  lineCount: number;
  /** Bearing used for the flight lines (field mode), null in route mode. */
  lineAngleDeg: number | null;
  /** Transit legs between flight lines that leave the field boundary (field mode). */
  transitsOutside: number;
}

export interface PhotoPoint extends LatLng {
  index: number;
  /** Leg the photo is taken on and the fraction (0..1) along that leg. */
  legIndex: number;
  legFraction: number;
}
