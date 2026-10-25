import { describe, expect, it } from 'vitest';
import {
  bearingDeg,
  findSelfIntersection,
  haversineM,
  localProjection,
  pointInPolygon,
  polygonAreaM2,
  segmentInsidePolygon,
} from './geo';
import { ORIGIN, rectangle } from './testFixtures';

describe('geo', () => {
  it('measures distances on the earth', () => {
    // 0.01° of longitude at 52° N is about 684.6 m.
    expect(haversineM({ lat: 52, lng: 5 }, { lat: 52, lng: 5.01 })).toBeCloseTo(684.6, 0);
    expect(haversineM(ORIGIN, ORIGIN)).toBe(0);
  });

  it('gives compass bearings', () => {
    expect(bearingDeg({ lat: 52, lng: 5 }, { lat: 52.01, lng: 5 })).toBeCloseTo(0, 3);
    expect(bearingDeg({ lat: 52, lng: 5 }, { lat: 52, lng: 5.01 })).toBeCloseTo(90, 1);
    expect(bearingDeg({ lat: 52, lng: 5 }, { lat: 51.99, lng: 5 })).toBeCloseTo(180, 3);
  });

  it('projects to metres and back', () => {
    const proj = localProjection(ORIGIN);
    const p = { lat: 52.503, lng: 5.497 };
    const back = proj.toLatLng(proj.toXY(p));
    expect(back.lat).toBeCloseTo(p.lat, 10);
    expect(back.lng).toBeCloseTo(p.lng, 10);
  });

  it('computes polygon areas', () => {
    expect(polygonAreaM2(rectangle(100, 100))).toBeCloseTo(10000, -1);
    expect(polygonAreaM2(rectangle(200, 50))).toBeCloseTo(10000, -1);
  });

  it('detects self-intersecting boundaries', () => {
    const square = [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 0, y: 10 },
    ];
    const bowtie = [
      { x: 0, y: 0 },
      { x: 10, y: 10 },
      { x: 10, y: 0 },
      { x: 0, y: 10 },
    ];
    expect(findSelfIntersection(square)).toBeNull();
    expect(findSelfIntersection(bowtie)).not.toBeNull();
  });

  it('knows what is inside a concave polygon', () => {
    const l = [
      { x: 0, y: 0 },
      { x: 20, y: 0 },
      { x: 20, y: 10 },
      { x: 10, y: 10 },
      { x: 10, y: 20 },
      { x: 0, y: 20 },
    ];
    expect(pointInPolygon({ x: 5, y: 15 }, l)).toBe(true);
    expect(pointInPolygon({ x: 15, y: 15 }, l)).toBe(false);
    expect(segmentInsidePolygon({ x: 2, y: 2 }, { x: 18, y: 2 }, l)).toBe(true);
    expect(segmentInsidePolygon({ x: 5, y: 15 }, { x: 18, y: 5 }, l)).toBe(false);
  });
});
