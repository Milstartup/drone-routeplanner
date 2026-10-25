import { describe, expect, it } from 'vitest';
import { analyzePlan } from './analysis';
import { makeId } from './defaults';
import { createPlanFile, parsePlanFile, PLAN_FILE_FORMAT, serializePlanFile } from './planFile';
import { fieldPlan, fromMeters, rectangle } from './testFixtures';

const [home] = fromMeters([[-10, -10]]);

function exported() {
  const plan = { ...fieldPlan(rectangle(200, 100), { home }), name: 'Broccoli noord' };
  const analysis = analyzePlan(plan);
  return { plan, analysis, file: createPlanFile(plan, analysis, new Date('2026-10-25T12:00:00Z')) };
}

describe('plan file', () => {
  it('says clearly that it is not a DJI mission', () => {
    const { file } = exported();
    expect(file.format).toBe(PLAN_FILE_FORMAT);
    expect(file.notice).toContain('GEEN DJI-missiebestand');
  });

  it('stores GPS coordinates of waypoints and photos', () => {
    const { file, analysis } = exported();
    expect(file.derived.waypoints).toHaveLength(analysis.route.waypoints.length);
    expect(file.derived.photoPoints).toHaveLength(analysis.photos.length);
    expect(file.derived.waypoints[0].altitudeM).toBe(30);
    expect(file.coordinateSystem).toContain('WGS84');
  });

  it('loads what it saved', () => {
    const { plan, file } = exported();
    const result = parsePlanFile(serializePlanFile(file), makeId);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.plan.name).toBe('Broccoli noord');
    expect(result.plan.mode).toBe('field');
    expect(result.plan.settings).toEqual(plan.settings);
    expect(result.plan.assumptions).toEqual(plan.assumptions);
    expect(result.plan.boundary).toHaveLength(4);
    result.plan.boundary.forEach((p, i) => {
      expect(p.lat).toBeCloseTo(plan.boundary[i].lat, 6);
      expect(p.lng).toBeCloseTo(plan.boundary[i].lng, 6);
    });
    expect(analyzePlan(result.plan).photos).toHaveLength(analyzePlan(plan).photos.length);
  });

  it('rejects broken or foreign files', () => {
    expect(parsePlanFile('{niet json', makeId)).toEqual({ ok: false, error: 'Dit is geen geldig JSON-bestand.' });
    const foreign = parsePlanFile(JSON.stringify({ mission: [] }), makeId);
    expect(foreign.ok).toBe(false);
  });

  it('rejects invalid coordinates and settings', () => {
    const { file } = exported();
    const badPoint = { ...file, boundary: [{ lat: 123, lng: 5 }, ...file.boundary.slice(1)] };
    const r1 = parsePlanFile(JSON.stringify(badPoint), makeId);
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error).toContain('Punt 1');

    const badSettings = { ...file, settings: { ...file.settings, altitudeM: 'hoog' } };
    const r2 = parsePlanFile(JSON.stringify(badSettings), makeId);
    expect(r2.ok).toBe(false);
    if (!r2.ok) expect(r2.error).toContain('settings.altitudeM');
  });
});
