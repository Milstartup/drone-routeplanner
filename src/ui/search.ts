// Place search with the PDOK Locatieserver (free, open, Netherlands only), or a typed coordinate.
import { parseCoordinates } from '../core/coords';
import type { LatLng } from '../core/types';

export interface SearchResult {
  label: string;
  type: string;
  at: LatLng;
}

const PDOK_SEARCH = 'https://api.pdok.nl/bzk/locatieserver/search/v3_1/free';

export async function searchPlaces(query: string, signal?: AbortSignal): Promise<SearchResult[]> {
  const coord = parseCoordinates(query);
  if (coord) return [{ label: `${coord.lat}, ${coord.lng}`, type: 'coördinaat', at: coord }];

  const url = `${PDOK_SEARCH}?q=${encodeURIComponent(query)}&rows=6&fl=weergavenaam,centroide_ll,type`;
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error(`Zoekdienst gaf status ${response.status}`);
  const data = (await response.json()) as { response?: { docs?: Record<string, unknown>[] } };
  const results: SearchResult[] = [];
  for (const doc of data.response?.docs ?? []) {
    const m = String(doc.centroide_ll ?? '').match(/POINT\(([-\d.]+) ([-\d.]+)\)/);
    if (!m) continue;
    results.push({
      label: String(doc.weergavenaam ?? ''),
      type: String(doc.type ?? ''),
      at: { lat: Number(m[2]), lng: Number(m[1]) },
    });
  }
  return results;
}
