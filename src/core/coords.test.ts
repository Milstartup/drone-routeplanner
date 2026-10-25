import { describe, expect, it } from 'vitest';
import { parseCoordinates } from './coords';

describe('parseCoordinates', () => {
  it('reads latitude and longitude', () => {
    expect(parseCoordinates('52.3443, 5.4552')).toEqual({ lat: 52.3443, lng: 5.4552 });
    expect(parseCoordinates(' 52.3443 5.4552 ')).toEqual({ lat: 52.3443, lng: 5.4552 });
    expect(parseCoordinates('-33.9,18.4')).toEqual({ lat: -33.9, lng: 18.4 });
  });

  it('ignores place names and impossible values', () => {
    expect(parseCoordinates('Zeewolde')).toBeNull();
    expect(parseCoordinates('95, 5')).toBeNull();
    expect(parseCoordinates('52, 200')).toBeNull();
  });
});
