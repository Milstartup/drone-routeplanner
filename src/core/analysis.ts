// One call that derives everything the UI shows from a plan.
import { groundFootprint, type Footprint } from './camera';
import { estimatePlan, type Estimate } from './estimate';
import { planPhotos } from './photos';
import { buildRoute } from './route';
import { buildTimeline, type Timeline } from './timeline';
import type { PhotoPoint, Plan, PlannedRoute } from './types';
import { validatePlan, type Issue } from './validate';

export interface PlanAnalysis {
  route: PlannedRoute;
  photos: PhotoPoint[];
  timeline: Timeline;
  estimate: Estimate;
  footprint: Footprint | null;
  issues: Issue[];
  hasErrors: boolean;
}

export function analyzePlan(plan: Plan): PlanAnalysis {
  const route = buildRoute(plan);
  const photos = planPhotos(route.legs, plan.settings.speedMps * plan.settings.photoIntervalS);
  const timeline = buildTimeline({
    route,
    photos,
    home: plan.home,
    settings: plan.settings,
    assumptions: plan.assumptions,
  });
  const footprint = groundFootprint(plan.settings.altitudeM);
  const estimate = estimatePlan(plan, route, photos, timeline, footprint);
  const issues = validatePlan(plan, { route, estimate, footprint });
  return { route, photos, timeline, estimate, footprint, issues, hasErrors: issues.some((i) => i.level === 'error') };
}
