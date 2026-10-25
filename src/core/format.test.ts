import { describe, expect, it } from 'vitest';
import { formatArea, formatDistance, formatDuration } from './format';

describe('format', () => {
  it('formats durations', () => {
    expect(formatDuration(5)).toBe('0:05');
    expect(formatDuration(125)).toBe('2:05');
    expect(formatDuration(3725)).toBe('1:02:05');
  });

  it('formats distances and areas the Dutch way', () => {
    expect(formatDistance(850)).toBe('850 m');
    expect(formatDistance(2345)).toBe('2,35 km');
    expect(formatArea(25000)).toBe('2,50 ha');
  });
});
