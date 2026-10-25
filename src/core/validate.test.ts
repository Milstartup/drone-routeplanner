import { describe, expect, it } from 'vitest';
import { analyzePlan } from './analysis';
import { fieldPlan, fromMeters, rectangle, routePlan } from './testFixtures';
import type { FlightSettings, Plan } from './types';

const [home] = fromMeters([[-10, -10]]);

function codes(plan: Plan, level?: 'error' | 'warning'): string[] {
  return analyzePlan(plan)
    .issues.filter((i) => !level || i.level === level)
    .map((i) => i.code);
}

function withSettings(changes: Partial<FlightSettings>): Plan {
  const plan = fieldPlan(rectangle(200, 100), { home });
  return { ...plan, settings: { ...plan.settings, ...changes } };
}

describe('validatePlan', () => {
  it('accepts a normal field plan', () => {
    expect(codes(fieldPlan(rectangle(200, 100), { home }), 'error')).toEqual([]);
  });

  it('rejects boundaries with too few points', () => {
    expect(codes(fieldPlan(rectangle(200, 100).slice(0, 2), { home }))).toContain('boundary-too-few');
  });

  it('rejects a boundary that crosses itself', () => {
    const bowtie = fromMeters([
      [0, 0],
      [100, 100],
      [100, 0],
      [0, 100],
    ]);
    const result = analyzePlan(fieldPlan(bowtie, { home }));
    expect(result.issues.map((i) => i.code)).toContain('boundary-self-intersect');
    expect(result.route.waypoints).toHaveLength(0);
  });

  it('rejects duplicate boundary points', () => {
    const b = fromMeters([
      [0, 0],
      [100, 0],
      [100, 0.1],
      [100, 100],
      [0, 100],
    ]);
    expect(codes(fieldPlan(b, { home }))).toContain('boundary-duplicate');
  });

  it('rejects tiny fields', () => {
    expect(codes(fieldPlan(rectangle(5, 5), { home }))).toContain('boundary-small');
  });

  it('reports when no lines fit', () => {
    expect(codes(withSettings({ edgeMarginM: 60 }))).toContain('no-lines');
  });

  it('checks the altitude', () => {
    expect(codes(withSettings({ altitudeM: Number.NaN }))).toContain('altitude-invalid');
    expect(codes(withSettings({ altitudeM: 3 }))).toContain('altitude-low');
    expect(codes(withSettings({ altitudeM: 150 }))).toContain('altitude-high');
    expect(codes(withSettings({ altitudeM: 10 }), 'warning')).toContain('altitude-lowish');
  });

  it('checks the speed', () => {
    expect(codes(withSettings({ speedMps: 0 }))).toContain('speed-invalid');
    expect(codes(withSettings({ speedMps: 9 }))).toContain('speed-high');
    expect(codes(withSettings({ speedMps: 8 }), 'error')).toEqual([]);
    expect(codes(withSettings({ speedMps: 7 }), 'warning')).toContain('speed-fast');
  });

  it('checks spacing, interval, margin and direction', () => {
    expect(codes(withSettings({ lineSpacingM: 1 }))).toContain('spacing-small');
    expect(codes(withSettings({ photoIntervalS: 0 }))).toContain('interval-small');
    expect(codes(withSettings({ photoIntervalS: 1 }), 'warning')).toContain('interval-short');
    expect(codes(withSettings({ edgeMarginM: -1 }))).toContain('margin-invalid');
    expect(codes(withSettings({ lineAngleDeg: Number.NaN }))).toContain('angle-invalid');
  });

  it('warns about gaps between photos', () => {
    // At 30 m one photo covers about 42 m x 32 m.
    expect(codes(withSettings({ lineSpacingM: 60 }), 'warning')).toContain('side-gap');
    expect(codes(withSettings({ speedMps: 8, photoIntervalS: 5 }), 'warning')).toContain('front-gap');
  });

  it('warns when the flight takes longer than one battery', () => {
    const plan = fieldPlan(rectangle(1000, 500), { home, settings: { lineSpacingM: 10 } as FlightSettings });
    expect(codes(plan, 'warning')).toContain('battery');
  });

  it('warns about a missing or far away take-off point', () => {
    expect(codes(fieldPlan(rectangle(200, 100)), 'warning')).toContain('home-missing');
    const [farHome] = fromMeters([[-2000, 0]]);
    expect(codes(fieldPlan(rectangle(200, 100), { home: farHome }), 'warning')).toContain('home-far');
  });

  it('checks manual routes', () => {
    expect(codes(routePlan(fromMeters([[0, 0]]), { home }))).toContain('route-too-few');
    const ok = routePlan(fromMeters([[0, 0], [100, 0], [100, 50]]), { home });
    expect(codes(ok, 'error')).toEqual([]);
  });

  it('rejects invalid coordinates', () => {
    const plan = routePlan([{ lat: 100, lng: 5 }, { lat: 52, lng: 5 }]);
    expect(codes(plan)).toContain('coord-invalid');
  });
});
