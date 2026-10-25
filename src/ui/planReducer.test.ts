import { describe, expect, it } from 'vitest';
import { createEmptyPlan } from '../core/defaults';
import type { Plan } from '../core/types';
import { historyReducer, planReducer, type HistoryState } from './planReducer';

const start = (): HistoryState => ({ past: [], present: createEmptyPlan(), future: [], lastKey: null });

describe('planReducer', () => {
  it('keeps the photo setting of each leg when a route is reversed', () => {
    let plan: Plan = { ...createEmptyPlan(), mode: 'route' };
    for (const lng of [5.0, 5.001, 5.002, 5.003]) plan = planReducer(plan, { type: 'addPoint', target: 'route', at: { lat: 52, lng } });
    // Leg 2 (5.001 -> 5.002) without photos.
    plan = planReducer(plan, { type: 'setCapture', id: plan.routePoints[1].id, capture: false });
    const reversed = planReducer(plan, { type: 'reverseRoute' });
    expect(reversed.routePoints.map((p) => p.lng)).toEqual([5.003, 5.002, 5.001, 5.0]);
    // Reversed leg 2 is 5.002 -> 5.001, the same stretch.
    expect(reversed.routePoints.map((p) => p.capture).slice(0, 3)).toEqual([true, false, true]);
  });

  it('inserts a point between two others', () => {
    let plan = createEmptyPlan();
    plan = planReducer(plan, { type: 'addPoint', target: 'boundary', at: { lat: 52, lng: 5 } });
    plan = planReducer(plan, { type: 'addPoint', target: 'boundary', at: { lat: 52, lng: 5.01 } });
    plan = planReducer(plan, { type: 'insertPoint', target: 'boundary', index: 1, at: { lat: 52.005, lng: 5.005 } });
    expect(plan.boundary.map((p) => p.lat)).toEqual([52, 52.005, 52]);
  });
});

describe('historyReducer', () => {
  it('turns one drag into one undo step', () => {
    let state = historyReducer(start(), { type: 'addPoint', target: 'boundary', at: { lat: 52, lng: 5 } });
    const id = state.present.boundary[0].id;
    state = historyReducer(state, { type: 'checkpoint' });
    for (const lat of [52.001, 52.002, 52.003]) state = historyReducer(state, { type: 'movePoint', target: 'boundary', id, at: { lat, lng: 5 } });
    expect(state.present.boundary[0].lat).toBe(52.003);
    state = historyReducer(state, { type: 'undo' });
    expect(state.present.boundary[0].lat).toBe(52);
    state = historyReducer(state, { type: 'redo' });
    expect(state.present.boundary[0].lat).toBe(52.003);
  });

  it('turns typing in one field into one undo step', () => {
    let state = start();
    for (const altitudeM of [4, 40, 45]) state = historyReducer(state, { type: 'updateSettings', changes: { altitudeM } });
    state = historyReducer(state, { type: 'undo' });
    expect(state.present.settings.altitudeM).toBe(30);
  });
});
