// Ground footprint of one photo, assuming the camera points straight down over flat ground
// and the long side of the photo lies across the flight direction.
import { DEG } from './geo';
import { MAVIC_MINI } from './mavicMini';

export interface CameraModel {
  diagonalFovDeg: number;
  imageWidthPx: number;
  imageHeightPx: number;
}

export interface Footprint {
  /** Ground width across the flight direction (m). */
  widthM: number;
  /** Ground length along the flight direction (m). */
  lengthM: number;
  /** Ground sample distance: centimetres of ground per pixel. */
  gsdCm: number;
}

export const DEFAULT_CAMERA: CameraModel = MAVIC_MINI.camera;

export function groundFootprint(altitudeM: number, camera: CameraModel = DEFAULT_CAMERA): Footprint | null {
  if (!(altitudeM > 0)) return null;
  const diagonalM = 2 * altitudeM * Math.tan((camera.diagonalFovDeg * DEG) / 2);
  const diagonalPx = Math.hypot(camera.imageWidthPx, camera.imageHeightPx);
  const widthM = (diagonalM * camera.imageWidthPx) / diagonalPx;
  const lengthM = (diagonalM * camera.imageHeightPx) / diagonalPx;
  return { widthM, lengthM, gsdCm: (widthM / camera.imageWidthPx) * 100 };
}

/** Overlap between neighbouring photos (0.6 = 60 %). Negative means a gap. */
export function overlapFraction(footprintM: number, distanceM: number): number {
  return 1 - distanceM / footprintM;
}
