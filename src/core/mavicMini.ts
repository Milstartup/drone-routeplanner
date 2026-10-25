// Specifications of the original DJI Mavic Mini (2019) used for estimates and checks.
// Source: official DJI spec page https://www.dji.com/mavic-mini/specs
// (now redirects to https://www.dji.com/support/product/mavic-mini), checked 2026-10-25.
// These are manufacturer figures in ideal conditions; the planner treats them as limits,
// not as what you will get in the field. The interval photo mode goes down to 2 s.

export const MAVIC_MINI = {
  /** Maximum horizontal speed per flight mode (m/s). */
  maxSpeedMps: { sport: 13, position: 8, cine: 4 },
  /** Maximum ascent speed per flight mode (m/s). */
  maxAscentMps: { sport: 4, position: 2, cine: 1.5 },
  /** Maximum descent speed per flight mode (m/s). */
  maxDescentMps: { sport: 3, position: 1.8, cine: 1 },
  /** Maximum flight time of the 249 g version, no wind, at 14 km/h (minutes). */
  maxFlightTimeMin: 30,
  camera: {
    sensor: '1/2.3" CMOS, 12 MP',
    /** Diagonal field of view of the lens (degrees). */
    diagonalFovDeg: 83,
    /** Photo size in 4:3 (pixels). */
    imageWidthPx: 4000,
    imageHeightPx: 3000,
  },
} as const;

/** Legal limit in the EU open category: 120 m above the closest point of the ground. */
export const EU_MAX_ALTITUDE_M = 120;
