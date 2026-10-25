// Plan editing with undo/redo. Typing in one input or one drag counts as one undo step.
import { makeId } from '../core/defaults';
import type { Assumptions, FlightSettings, LatLng, Plan, PlanMode } from '../core/types';

export type PointTarget = 'route' | 'boundary';

export type PlanAction =
  | { type: 'setName'; name: string }
  | { type: 'setMode'; mode: PlanMode }
  | { type: 'addPoint'; target: PointTarget; at: LatLng }
  | { type: 'insertPoint'; target: PointTarget; index: number; at: LatLng }
  | { type: 'movePoint'; target: PointTarget; id: string; at: LatLng }
  | { type: 'deletePoint'; target: PointTarget; id: string }
  | { type: 'clearPoints'; target: PointTarget }
  | { type: 'reverseRoute' }
  | { type: 'setCapture'; id: string; capture: boolean }
  | { type: 'setHome'; at: LatLng | null }
  | { type: 'updateSettings'; changes: Partial<FlightSettings> }
  | { type: 'updateAssumptions'; changes: Partial<Assumptions> }
  | { type: 'replacePlan'; plan: Plan }
  | { type: 'useGeneratedRoute'; waypoints: LatLng[]; capture: boolean[] };

function updatePoints(plan: Plan, target: PointTarget, fn: <T extends { id: string }>(pts: T[]) => T[]): Plan {
  return target === 'route' ? { ...plan, routePoints: fn(plan.routePoints) } : { ...plan, boundary: fn(plan.boundary) };
}

export function planReducer(plan: Plan, action: PlanAction): Plan {
  switch (action.type) {
    case 'setName':
      return { ...plan, name: action.name };
    case 'setMode':
      return plan.mode === action.mode ? plan : { ...plan, mode: action.mode };
    case 'addPoint': {
      const at = { lat: action.at.lat, lng: action.at.lng };
      return action.target === 'route'
        ? { ...plan, routePoints: [...plan.routePoints, { id: makeId(), ...at, capture: true }] }
        : { ...plan, boundary: [...plan.boundary, { id: makeId(), ...at }] };
    }
    case 'insertPoint': {
      const at = { lat: action.at.lat, lng: action.at.lng };
      if (action.target === 'route') {
        const pts = [...plan.routePoints];
        const before = pts[action.index - 1];
        pts.splice(action.index, 0, { id: makeId(), ...at, capture: before ? before.capture : true });
        return { ...plan, routePoints: pts };
      }
      const pts = [...plan.boundary];
      pts.splice(action.index, 0, { id: makeId(), ...at });
      return { ...plan, boundary: pts };
    }
    case 'movePoint':
      return updatePoints(plan, action.target, (pts) =>
        pts.map((p) => (p.id === action.id ? { ...p, lat: action.at.lat, lng: action.at.lng } : p)),
      );
    case 'deletePoint':
      return updatePoints(plan, action.target, (pts) => pts.filter((p) => p.id !== action.id));
    case 'clearPoints':
      return updatePoints(plan, action.target, () => []);
    case 'reverseRoute': {
      // Leg i (from point i to i + 1) keeps its photo setting after reversing.
      const pts = plan.routePoints;
      const reversed = [...pts].reverse().map((p, i, arr) => ({
        ...p,
        capture: i < arr.length - 1 ? pts[pts.length - 2 - i].capture : true,
      }));
      return { ...plan, routePoints: reversed };
    }
    case 'setCapture':
      return {
        ...plan,
        routePoints: plan.routePoints.map((p) => (p.id === action.id ? { ...p, capture: action.capture } : p)),
      };
    case 'setHome':
      return { ...plan, home: action.at ? { lat: action.at.lat, lng: action.at.lng } : null };
    case 'updateSettings':
      return { ...plan, settings: { ...plan.settings, ...action.changes } };
    case 'updateAssumptions':
      return { ...plan, assumptions: { ...plan.assumptions, ...action.changes } };
    case 'replacePlan':
      return action.plan;
    case 'useGeneratedRoute':
      return {
        ...plan,
        mode: 'route',
        routePoints: action.waypoints.map((p, i) => ({
          id: makeId(),
          lat: p.lat,
          lng: p.lng,
          capture: action.capture[i] ?? true,
        })),
      };
  }
}

export interface HistoryState {
  past: Plan[];
  present: Plan;
  future: Plan[];
  /** Actions with the same key directly after each other are merged into one undo step. */
  lastKey: string | null;
}

export type HistoryAction = PlanAction | { type: 'undo' } | { type: 'redo' } | { type: 'checkpoint' };

const HISTORY_LIMIT = 100;

function mergeKey(action: PlanAction): string | null {
  switch (action.type) {
    case 'setName':
      return 'name';
    case 'updateSettings':
      return `settings:${Object.keys(action.changes).join(',')}`;
    case 'updateAssumptions':
      return `assumptions:${Object.keys(action.changes).join(',')}`;
    case 'movePoint':
      return `move:${action.id}`;
    default:
      return null;
  }
}

export function historyReducer(state: HistoryState, action: HistoryAction): HistoryState {
  if (action.type === 'checkpoint') return { ...state, lastKey: null };
  if (action.type === 'undo') {
    if (state.past.length === 0) return state;
    return {
      past: state.past.slice(0, -1),
      present: state.past[state.past.length - 1],
      future: [state.present, ...state.future],
      lastKey: null,
    };
  }
  if (action.type === 'redo') {
    if (state.future.length === 0) return state;
    return {
      past: [...state.past, state.present],
      present: state.future[0],
      future: state.future.slice(1),
      lastKey: null,
    };
  }
  const next = planReducer(state.present, action);
  if (next === state.present) return state;
  const key = mergeKey(action);
  if (key !== null && key === state.lastKey) return { ...state, present: next };
  return {
    past: [...state.past, state.present].slice(-HISTORY_LIMIT),
    present: next,
    future: [],
    lastKey: key,
  };
}
