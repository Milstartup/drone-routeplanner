// Reference files for the Swift port of the field-route generation (ios/).
//
// Builds three field plans with the planner's own core and compares the saved plan file with
// the files in docs/voorbeelden/. The Swift code is tested against those files.
//
// Regenerate the files after a deliberate change to the core:
//   UPDATE_FIXTURES=1 npm test
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { analyzePlan } from '../core/analysis';
import { createEmptyPlan } from '../core/defaults';
import { createPlanFile, serializePlanFile } from '../core/planFile';
import type { FlightSettings, LatLng, Plan } from '../core/types';

const CREATED_AT = new Date('2026-10-27T10:00:00.000Z');
const UPDATE = process.env.UPDATE_FIXTURES === '1';

function fieldPlan(name: string, boundary: [number, number][], home: [number, number], settings?: FlightSettings): Plan {
  const plan = createEmptyPlan();
  const point = ([lat, lng]: [number, number]): LatLng => ({ lat, lng });
  return {
    ...plan,
    name,
    mode: 'field',
    home: point(home),
    routePoints: [],
    boundary: boundary.map((p, i) => ({ id: `b${i + 1}`, ...point(p) })),
    settings: settings ?? plan.settings,
  };
}

const FIXTURES: { file: string; plan: Plan }[] = [
  {
    // L-shaped field near Dronten, planner default settings (automatic line angle).
    file: 'voorbeeld-veld.routeplan.json',
    plan: fieldPlan(
      'Voorbeeldveld L-vorm',
      [
        [52.49800, 5.54000],
        [52.49800, 5.54250],
        [52.49900, 5.54250],
        [52.49900, 5.54120],
        [52.50010, 5.54120],
        [52.50010, 5.54000],
      ],
      [52.49790, 5.53995],
    ),
  },
  {
    // Skewed four-sided field with a fixed line angle and non-default settings.
    file: 'voorbeeld-veld-schuin.routeplan.json',
    plan: fieldPlan(
      'Voorbeeldveld schuin',
      [
        [52.49750, 5.54400],
        [52.49760, 5.54620],
        [52.49890, 5.54600],
        [52.49870, 5.54390],
      ],
      [52.49745, 5.54395],
      { altitudeM: 35, speedMps: 5, lineSpacingM: 18, photoIntervalS: 2.5, lineAngleDeg: 60, edgeMarginM: 3 },
    ),
  },
  {
    // U-shaped field: scan lines in the arms give two pieces, and some transits cross the notch.
    file: 'voorbeeld-veld-u.routeplan.json',
    plan: fieldPlan(
      'Voorbeeldveld U-vorm',
      [
        [52.49600, 5.54000],
        [52.49600, 5.54300],
        [52.49750, 5.54300],
        [52.49750, 5.54200],
        [52.49650, 5.54200],
        [52.49650, 5.54100],
        [52.49750, 5.54100],
        [52.49750, 5.54000],
      ],
      [52.49595, 5.53995],
      { altitudeM: 30, speedMps: 4, lineSpacingM: 25, photoIntervalS: 3, lineAngleDeg: null, edgeMarginM: 5 },
    ),
  },
];

describe('field reference files (docs/voorbeelden)', () => {
  it.each(FIXTURES)('$file matches the planner output', ({ file, plan }) => {
    const analysis = analyzePlan(plan);
    expect(analysis.issues.filter((i) => i.level === 'error')).toEqual([]);
    expect(analysis.hasErrors).toBe(false);
    expect(analysis.route.lineCount).toBeGreaterThan(0);

    // Files end with a newline, like the other example files.
    const text = serializePlanFile(createPlanFile(plan, analysis, CREATED_AT)) + '\n';
    const path = fileURLToPath(new URL(`../../docs/voorbeelden/${file}`, import.meta.url));
    if (UPDATE) writeFileSync(path, text, 'utf8');
    expect(readFileSync(path, 'utf8')).toBe(text);
  });
});
