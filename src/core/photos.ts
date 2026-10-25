// Photo positions along the route. A photo is planned every `spacing` metres on legs that
// take photos; a run of consecutive photo legs counts as one continuous stretch, so a corner
// does not produce a double photo. Each new stretch (for example a new flight line) starts
// with a photo at its first point.
import { haversineM, interpolate } from './geo';
import type { PhotoPoint, RouteLeg } from './types';

/** Safety cap so a tiny interval cannot freeze the browser. */
export const MAX_PHOTOS = 20000;
/** A photo due within this distance after the end of a leg is still taken at the end. */
const END_TOLERANCE_M = 0.1;

export function planPhotos(legs: RouteLeg[], spacingM: number): PhotoPoint[] {
  const photos: PhotoPoint[] = [];
  if (!(spacingM > 0)) return photos;
  let inRun = false;
  let runDistance = 0;
  let nextAt = 0;
  legs.forEach((leg, legIndex) => {
    if (!leg.capture) {
      inRun = false;
      return;
    }
    if (!inRun) {
      inRun = true;
      runDistance = 0;
      nextAt = 0;
    }
    const len = haversineM(leg.from, leg.to);
    while (nextAt <= runDistance + len + END_TOLERANCE_M && photos.length < MAX_PHOTOS) {
      const f = len > 0 ? Math.min(1, Math.max(0, (nextAt - runDistance) / len)) : 0;
      photos.push({ index: photos.length, legIndex, legFraction: f, ...interpolate(leg.from, leg.to, f) });
      nextAt += spacingM;
    }
    runDistance += len;
  });
  return photos;
}
