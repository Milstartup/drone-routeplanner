import { useRef } from 'react';
import type { SavedPlan } from '../storage';

interface Props {
  name: string;
  canExport: boolean;
  saved: SavedPlan[];
  message: { kind: 'ok' | 'error'; text: string } | null;
  disabled: boolean;
  onNameChange(name: string): void;
  onDownload(): void;
  onLoadFile(file: File): void;
  onSaveInBrowser(): void;
  onLoadSaved(entry: SavedPlan): void;
  onDeleteSaved(entry: SavedPlan): void;
  onNewPlan(): void;
}

export function FilePanel(props: Props) {
  const fileInput = useRef<HTMLInputElement>(null);
  return (
    <section className="panel">
      <h2>Opslaan en laden</h2>
      <div className="field">
        <label htmlFor="plan-name">Naam van de route</label>
        <input id="plan-name" type="text" value={props.name} disabled={props.disabled} onChange={(e) => props.onNameChange(e.target.value)} />
      </div>
      <div className="buttons">
        <button type="button" className="primary" disabled={!props.canExport} onClick={props.onDownload}>
          Download JSON
        </button>
        <button type="button" disabled={props.disabled} onClick={() => fileInput.current?.click()}>
          JSON laden
        </button>
        <input
          ref={fileInput}
          type="file"
          accept=".json,application/json"
          hidden
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) props.onLoadFile(file);
            e.target.value = '';
          }}
        />
      </div>
      <p className="help small">
        Het JSON-bestand bevat de route met GPS-coördinaten (WGS84) en de instellingen. Het is een <b>planningsbestand</b>, geen
        DJI-missie: een DJI-drone of de DJI Fly-app kan het niet uitvoeren.
      </p>
      {props.message && <p className={props.message.kind === 'error' ? 'msg msg--error' : 'msg msg--ok'}>{props.message.text}</p>}

      <div className="list-head">
        <span>Opgeslagen in deze browser ({props.saved.length})</span>
        <span className="buttons buttons--small">
          <button type="button" disabled={props.disabled} onClick={props.onSaveInBrowser}>
            Opslaan
          </button>
          <button type="button" disabled={props.disabled} onClick={props.onNewPlan}>
            Nieuw plan
          </button>
        </span>
      </div>
      {props.saved.length > 0 && (
        <ul className="saved">
          {props.saved.map((s) => (
            <li key={s.id}>
              <span>
                {s.name} <span className="muted small">{new Date(s.savedAt).toLocaleString('nl-NL')}</span>
              </span>
              <span className="buttons buttons--small">
                <button type="button" disabled={props.disabled} onClick={() => props.onLoadSaved(s)}>
                  Laden
                </button>
                <button type="button" className="icon" aria-label={`${s.name} verwijderen`} onClick={() => props.onDeleteSaved(s)}>
                  ×
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
      <p className="muted small">Je huidige plan wordt ook automatisch bewaard in deze browser.</p>
    </section>
  );
}
