import { describe, expect, it } from 'vitest';
import { analyzePlan } from './analysis';
import { haversineM } from './geo';
import { photosTakenAt, stateAt } from './timeline';
import { fieldPlan, fromMeters, rectangle } from './testFixtures';

const [home] = fromMeters([[-20, 0]]);
const settings = { altitudeM: 30, speedMps: 4, lineSpacingM: 20, photoIntervalS: 5, lineAngleDeg: 90, edgeMarginM: 0 };
const assumptions = { ascentSpeedMps: 2, descentSpeedMps: 1.5, waypointPauseS: 3, usableFlightTimeS: 1200, maxDistanceFromHomeM: 500 };

describe('timeline and estimate', () => {
  it('climbs at the take-off point first', () => {
    const { timeline } = analyzePlan(fieldPlan(rectangle(200, 100), { home, settings, assumptions }));
    const s = stateAt(timeline, 7.5)!;
    expect(s.phase).toBe('climb');
    expect(s.altitudeM).toBeCloseTo(15, 5);
    expect(haversineM(s.position, home)).toBeLessThan(0.01);
  });

  it('adds up climb, flight, pauses and descent', () => {
    const { timeline, estimate } = analyzePlan(fieldPlan(rectangle(200, 100), { home, settings, assumptions }));
    expect(estimate.climbS).toBeCloseTo(15, 5);
    expect(estimate.descentS).toBeCloseTo(20, 5);
    // 10 waypoints, a pause on arrival at each.
    expect(estimate.pauseS).toBeCloseTo(30, 5);
    expect(estimate.flyS).toBeCloseTo(estimate.totalDistanceM / 4, 3);
    expect(estimate.totalS).toBeCloseTo(estimate.climbS + estimate.flyS + estimate.pauseS + estimate.descentS, 5);
    expect(timeline.totalS).toBe(estimate.totalS);
  });

  it('estimates lengths and photo counts for a simple field', () => {
    const { estimate } = analyzePlan(fieldPlan(rectangle(200, 100), { home, settings, assumptions }));
    expect(estimate.photoDistanceM).toBeCloseTo(1000, 0);
    expect(estimate.transitDistanceM).toBeCloseTo(80, 0);
    expect(estimate.photoSpacingM).toBe(20);
    // 5 lines of 200 m, a photo every 20 m: 11 per line.
    expect(estimate.photoCount).toBe(55);
    expect(estimate.fieldAreaM2).toBeCloseTo(20000, -1);
  });

  it('ends on the ground at the take-off point', () => {
    const { timeline, photos } = analyzePlan(fieldPlan(rectangle(200, 100), { home, settings, assumptions }));
    const end = stateAt(timeline, timeline.totalS + 1)!;
    expect(end.phase).toBe('done');
    expect(end.altitudeM).toBe(0);
    expect(haversineM(end.position, home)).toBeLessThan(0.01);
    expect(photosTakenAt(timeline, timeline.totalS)).toBe(photos.length);
  });

  it('takes photos in order while flying', () => {
    const { timeline } = analyzePlan(fieldPlan(rectangle(200, 100), { home, settings, assumptions }));
    const times = timeline.photoTimesS;
    for (let i = 1; i < times.length; i++) expect(times[i]).toBeGreaterThanOrEqual(times[i - 1]);
    expect(times[0]).toBeGreaterThan(15);
    expect(times[times.length - 1]).toBeLessThan(timeline.totalS);
    const atPhoto = stateAt(timeline, times[3] + 1e-6)!;
    expect(atPhoto.phase).toBe('fly');
    expect(atPhoto.capture).toBe(true);
  });

  it('starts at the first waypoint when there is no take-off point', () => {
    const { timeline, estimate } = analyzePlan(fieldPlan(rectangle(200, 100), { settings, assumptions }));
    expect(timeline.segments[0].phase).toBe('fly');
    expect(estimate.climbS).toBe(0);
    expect(estimate.homeDistanceM).toBe(0);
  });
});
