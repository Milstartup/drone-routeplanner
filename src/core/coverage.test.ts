import { describe, expect, it } from 'vitest';
import { generateCoverage } from './coverage';
import { distanceToPolygonEdges, haversineM, pointInPolygon, segmentInsidePolygon } from './geo';
import { fromMeters, originProjection, rectangle } from './testFixtures';
import type { LatLng } from './types';

const lengths = (legs: { from: LatLng; to: LatLng }[]) => legs.map((l) => haversineM(l.from, l.to));

describe('generateCoverage', () => {
  it('fills a 200 x 100 m field with east-west lines', () => {
    const res = generateCoverage(rectangle(200, 100), { lineSpacingM: 20, lineAngleDeg: 90, edgeMarginM: 0 });
    expect(res.lineCount).toBe(5);
    expect(res.waypoints).toHaveLength(10);
    expect(res.legs).toHaveLength(9);
    for (const len of lengths(res.legs.filter((l) => l.capture))) expect(len).toBeCloseTo(200, 0);
    for (const len of lengths(res.legs.filter((l) => !l.capture))) expect(len).toBeCloseTo(20, 0);
    expect(res.transitsOutside).toBe(0);
  });

  it('places the outer lines half a spacing from the edge', () => {
    const res = generateCoverage(rectangle(200, 100), { lineSpacingM: 20, lineAngleDeg: 90, edgeMarginM: 0 });
    const ys = res.waypoints.map((p) => originProjection.toXY(p).y);
    expect(Math.min(...ys)).toBeCloseTo(10, 1);
    expect(Math.max(...ys)).toBeCloseTo(90, 1);
  });

  it('follows the longest edge when the direction is automatic', () => {
    const res = generateCoverage(rectangle(200, 100), { lineSpacingM: 20, lineAngleDeg: null, edgeMarginM: 0 });
    expect(res.angleDeg).toBeCloseTo(90, 1);
    expect(res.lineCount).toBe(5);
  });

  it('uses the chosen direction', () => {
    const res = generateCoverage(rectangle(200, 100), { lineSpacingM: 20, lineAngleDeg: 0, edgeMarginM: 0 });
    expect(res.lineCount).toBe(10);
    for (const len of lengths(res.legs.filter((l) => l.capture))) expect(len).toBeCloseTo(100, 0);
  });

  it('keeps the edge margin', () => {
    const boundary = rectangle(200, 100);
    const res = generateCoverage(boundary, { lineSpacingM: 20, lineAngleDeg: 90, edgeMarginM: 5 });
    const poly = boundary.map(originProjection.toXY);
    for (const len of lengths(res.legs.filter((l) => l.capture))) expect(len).toBeCloseTo(190, 0);
    for (const p of res.waypoints) expect(distanceToPolygonEdges(originProjection.toXY(p), poly)).toBeGreaterThan(4.99);
  });

  it('stays inside a concave (L-shaped) field', () => {
    const boundary = fromMeters([
      [0, 0],
      [200, 0],
      [200, 60],
      [80, 60],
      [80, 160],
      [0, 160],
    ]);
    const poly = boundary.map(originProjection.toXY);
    const res = generateCoverage(boundary, { lineSpacingM: 15, lineAngleDeg: 90, edgeMarginM: 3 });
    expect(res.lineCount).toBeGreaterThan(5);
    for (const leg of res.legs.filter((l) => l.capture)) {
      const a = originProjection.toXY(leg.from);
      const b = originProjection.toXY(leg.to);
      expect(segmentInsidePolygon(a, b, poly)).toBe(true);
    }
    for (const p of res.waypoints) {
      const xy = originProjection.toXY(p);
      expect(pointInPolygon(xy, poly)).toBe(true);
      expect(distanceToPolygonEdges(xy, poly)).toBeGreaterThan(2.99);
    }
  });

  it('reports transits that leave a U-shaped field', () => {
    const boundary = fromMeters([
      [0, 0],
      [300, 0],
      [300, 200],
      [200, 200],
      [200, 60],
      [100, 60],
      [100, 200],
      [0, 200],
    ]);
    const res = generateCoverage(boundary, { lineSpacingM: 20, lineAngleDeg: 90, edgeMarginM: 2 });
    expect(res.transitsOutside).toBeGreaterThan(0);
  });

  it('returns no lines when the margin leaves no room', () => {
    const res = generateCoverage(rectangle(30, 30), { lineSpacingM: 10, lineAngleDeg: 90, edgeMarginM: 20 });
    expect(res.lineCount).toBe(0);
    expect(res.waypoints).toHaveLength(0);
  });

  it('starts at the line end nearest to the take-off point', () => {
    const [start] = fromMeters([[210, 105]]);
    const res = generateCoverage(rectangle(200, 100), {
      lineSpacingM: 20,
      lineAngleDeg: 90,
      edgeMarginM: 0,
      start,
    });
    expect(haversineM(res.waypoints[0], start)).toBeLessThan(25);
  });
});
