// Browser storage for the current plan (autosave) and for named saved plans.
// localStorage can be unavailable (private window, blocked site data), so every call is guarded.
import { makeId } from '../core/defaults';
import { parsePlanFile } from '../core/planFile';
import type { Plan } from '../core/types';

const CURRENT_KEY = 'drone-routeplanner.current.v1';
const SAVED_KEY = 'drone-routeplanner.saved.v1';
const PROVIDER_KEY = 'drone-routeplanner.provider.v1';

export interface SavedPlan {
  id: string;
  name: string;
  savedAt: string;
  /** Plan file JSON (same format as the download). */
  json: string;
}

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string): boolean {
  try {
    window.localStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

export function loadCurrentPlan(): Plan | null {
  const json = read(CURRENT_KEY);
  if (!json) return null;
  const result = parsePlanFile(json, makeId);
  return result.ok ? result.plan : null;
}

export function saveCurrentPlan(json: string): void {
  write(CURRENT_KEY, json);
}

export function listSavedPlans(): SavedPlan[] {
  const json = read(SAVED_KEY);
  if (!json) return [];
  try {
    const list = JSON.parse(json) as SavedPlan[];
    return Array.isArray(list) ? list.filter((p) => typeof p?.json === 'string') : [];
  } catch {
    return [];
  }
}

export function storeSavedPlans(list: SavedPlan[]): boolean {
  return write(SAVED_KEY, JSON.stringify(list));
}

export function loadProviderId(): string | null {
  return read(PROVIDER_KEY);
}

export function saveProviderId(id: string): void {
  write(PROVIDER_KEY, id);
}
