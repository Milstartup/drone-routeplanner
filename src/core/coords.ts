import { isValidLatLng } from './geo';
import type { LatLng } from './types';

/**
 * Reads "52.3443, 5.4552" or "52.3443 5.4552" (latitude first). Returns null for anything
 * else, so normal search text is passed on to the place search.
 */
export function parseCoordinates(text: string): LatLng | null {
  const m = text.trim().match(/^(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$/);
  if (!m) return null;
  const p = { lat: Number(m[1]), lng: Number(m[2]) };
  return isValidLatLng(p) ? p : null;
}
