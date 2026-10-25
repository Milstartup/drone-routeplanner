import { describe, expect, it } from 'vitest';
import { planPhotos } from './photos';
import { fromMeters } from './testFixtures';
import type { RouteLeg } from './types';

function legs(points: [number, number][], capture: boolean[]): RouteLeg[] {
  const ll = fromMeters(points);
  return ll.slice(0, -1).map((from, i) => ({ from, to: ll[i + 1], capture: capture[i] }));
}

describe('planPhotos', () => {
  it('places a photo every spacing metres including both ends', () => {
    const photos = planPhotos(legs([[0, 0], [100, 0]], [true]), 25);
    expect(photos).toHaveLength(5);
    expect(photos[0].legFraction).toBe(0);
    expect(photos[4].legFraction).toBeCloseTo(1, 3);
  });

  it('continues across a corner without a double photo', () => {
    const photos = planPhotos(legs([[0, 0], [60, 0], [60, 40]], [true, true]), 25);
    expect(photos).toHaveLength(5);
  });

  it('starts again after a leg without photos', () => {
    const photos = planPhotos(legs([[0, 0], [50, 0], [50, 20], [0, 20]], [true, false, true]), 25);
    expect(photos).toHaveLength(6);
    expect(photos.filter((p) => p.legIndex === 1)).toHaveLength(0);
  });

  it('plans nothing for an invalid spacing', () => {
    expect(planPhotos(legs([[0, 0], [100, 0]], [true]), 0)).toHaveLength(0);
    expect(planPhotos(legs([[0, 0], [100, 0]], [true]), Number.NaN)).toHaveLength(0);
  });
});
