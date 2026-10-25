import { useRef, useState } from 'react';
import type { LatLng } from '../../core/types';
import { MAP_PROVIDERS, type MapProvider } from '../../map/providers';
import { searchPlaces, type SearchResult } from '../search';

interface Props {
  provider: MapProvider;
  onProviderChange(id: string): void;
  onGoTo(at: LatLng): void;
  onFitPlan(): void;
  canFit: boolean;
}

export function MapSourcePanel({ provider, onProviderChange, onGoTo, onFitPlan, canFit }: Props) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const search = async () => {
    const q = query.trim();
    if (!q) return;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setMessage('Zoeken…');
    try {
      const found = await searchPlaces(q, controller.signal);
      setResults(found);
      setMessage(found.length === 0 ? 'Niets gevonden. Probeer een plaats, adres of "52.34, 5.45".' : null);
      if (found.length === 1) onGoTo(found[0].at);
    } catch (e) {
      if ((e as Error).name !== 'AbortError') setMessage('Zoeken lukt niet (geen internet of zoekdienst niet bereikbaar).');
    }
  };

  return (
    <section className="panel">
      <h2>Kaart</h2>
      <div className="field">
        <label htmlFor="provider">Kaartbeeld</label>
        <select id="provider" value={provider.id} onChange={(e) => onProviderChange(e.target.value)}>
          {MAP_PROVIDERS.map((p) => (
            <option key={p.id} value={p.id} disabled={!p.available}>
              {p.label}
            </option>
          ))}
        </select>
        <div className="field__hint">{provider.note}</div>
      </div>
      <form
        className="search"
        onSubmit={(e) => {
          e.preventDefault();
          void search();
        }}
      >
        <input
          type="search"
          placeholder="Plaats, adres of 52.34, 5.45"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Zoek een plaats"
        />
        <button type="submit">Zoek</button>
      </form>
      {message && <div className="field__hint">{message}</div>}
      {results.length > 1 && (
        <ul className="search__results">
          {results.map((r, i) => (
            <li key={i}>
              <button type="button" className="link" onClick={() => onGoTo(r.at)}>
                {r.label} <span className="muted">({r.type})</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <button type="button" onClick={onFitPlan} disabled={!canFit}>
        Zoom naar plan
      </button>
    </section>
  );
}
