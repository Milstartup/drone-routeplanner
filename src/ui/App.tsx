import { useCallback, useEffect, useMemo, useReducer, useState } from 'react';
import { analyzePlan } from '../core/analysis';
import { createEmptyPlan, makeId } from '../core/defaults';
import { formatDuration, formatNumber } from '../core/format';
import { createPlanFile, parsePlanFile, serializePlanFile } from '../core/planFile';
import { photosTakenAt, stateAt } from '../core/timeline';
import type { LatLng, Plan, PlanMode } from '../core/types';
import { DEFAULT_PROVIDER_ID, MAP_PROVIDERS } from '../map/providers';
import { MapView, type FocusRequest, type Tool } from './MapView';
import { DrawPanel } from './panels/DrawPanel';
import { EstimatePanel } from './panels/EstimatePanel';
import { FilePanel } from './panels/FilePanel';
import { IssuesPanel } from './panels/IssuesPanel';
import { MapSourcePanel } from './panels/MapSourcePanel';
import { SettingsPanel } from './panels/SettingsPanel';
import { phaseLabel, SimulationPanel } from './panels/SimulationPanel';
import { historyReducer, type HistoryState, type PointTarget } from './planReducer';
import {
  listSavedPlans,
  loadCurrentPlan,
  loadProviderId,
  saveCurrentPlan,
  saveProviderId,
  storeSavedPlans,
  type SavedPlan,
} from './storage';
import { useSimulation } from './useSimulation';

function planPoints(plan: Plan): LatLng[] {
  return [...plan.boundary, ...plan.routePoints, ...(plan.home ? [plan.home] : [])];
}

function fileSlug(name: string): string {
  const slug = name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  return slug || 'route';
}

function initialHistory(): HistoryState {
  return { past: [], present: loadCurrentPlan() ?? createEmptyPlan(), future: [], lastKey: null };
}

type FileMessage = { kind: 'ok' | 'error'; text: string } | null;

export function App() {
  const [history, dispatch] = useReducer(historyReducer, undefined, initialHistory);
  const plan = history.present;
  const analysis = useMemo(() => analyzePlan(plan), [plan]);

  const [tool, setTool] = useState<Tool>('none');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [providerId, setProviderId] = useState(() => {
    const id = loadProviderId();
    return MAP_PROVIDERS.some((p) => p.id === id && p.available) ? (id as string) : DEFAULT_PROVIDER_ID;
  });
  const provider = MAP_PROVIDERS.find((p) => p.id === providerId) ?? MAP_PROVIDERS[0];
  const [focus, setFocus] = useState<FocusRequest | null>(() => {
    const points = planPoints(history.present);
    return points.length > 0 ? { seq: 1, points } : null;
  });
  const [saved, setSaved] = useState<SavedPlan[]>(() => listSavedPlans());
  const [fileMessage, setFileMessage] = useState<FileMessage>(null);

  const clock = useSimulation(analysis.timeline.totalS, analysis);
  const simulating = clock.playing || clock.timeS > 0;
  const drone = simulating ? stateAt(analysis.timeline, clock.timeS) : null;
  const photosTaken = simulating ? photosTakenAt(analysis.timeline, clock.timeS) : 0;
  const editTarget: PointTarget = plan.mode === 'field' ? 'boundary' : 'route';

  const focusOn = useCallback((points: LatLng[]) => {
    if (points.length > 0) setFocus((f) => ({ seq: (f?.seq ?? 0) + 1, points }));
  }, []);

  // Autosave the current plan in this browser.
  useEffect(() => {
    const handle = window.setTimeout(() => saveCurrentPlan(serializePlanFile(createPlanFile(plan, analysis))), 400);
    return () => window.clearTimeout(handle);
  }, [plan, analysis]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setTool('none');
        return;
      }
      const el = e.target as HTMLElement | null;
      const typing = !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable);
      if (typing || simulating) return;
      const ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        dispatch({ type: e.shiftKey ? 'redo' : 'undo' });
      } else if (ctrl && e.key.toLowerCase() === 'y') {
        e.preventDefault();
        dispatch({ type: 'redo' });
      } else if ((e.key === 'Delete' || e.key === 'Backspace') && selectedId) {
        e.preventDefault();
        dispatch({ type: 'deletePoint', target: editTarget, id: selectedId });
        setSelectedId(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selectedId, editTarget, simulating]);

  const onMapClick = (at: LatLng) => {
    if (simulating) return;
    if (tool === 'home') {
      dispatch({ type: 'setHome', at });
      setTool('none');
    } else if (tool === 'add') {
      dispatch({ type: 'addPoint', target: editTarget, at });
    } else {
      setSelectedId(null);
    }
  };

  const changeMode = (mode: PlanMode) => {
    dispatch({ type: 'setMode', mode });
    setTool('none');
    setSelectedId(null);
  };

  const applyLoadedPlan = (loaded: Plan, text: string) => {
    dispatch({ type: 'replacePlan', plan: loaded });
    setTool('none');
    setSelectedId(null);
    setFileMessage({ kind: 'ok', text });
    focusOn(planPoints(loaded));
  };

  const download = () => {
    if (analysis.hasErrors) return;
    const json = serializePlanFile(createPlanFile(plan, analysis));
    const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${fileSlug(plan.name)}.routeplan.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    setFileMessage({ kind: 'ok', text: `Opgeslagen als ${a.download} (in je map Downloads).` });
  };

  const loadFile = async (file: File) => {
    const result = parsePlanFile(await file.text(), makeId);
    if (result.ok) applyLoadedPlan(result.plan, `${file.name} geladen.`);
    else setFileMessage({ kind: 'error', text: `${file.name} kan niet geladen worden: ${result.error}` });
  };

  const saveInBrowser = () => {
    const name = plan.name.trim() || 'Naamloze route';
    if (saved.some((s) => s.name === name) && !window.confirm(`Er is al een route "${name}" opgeslagen. Overschrijven?`)) return;
    const entry: SavedPlan = {
      id: makeId(),
      name,
      savedAt: new Date().toISOString(),
      json: serializePlanFile(createPlanFile(plan, analysis)),
    };
    const list = [entry, ...saved.filter((s) => s.name !== name)];
    if (storeSavedPlans(list)) {
      setSaved(list);
      setFileMessage({ kind: 'ok', text: `"${name}" is opgeslagen in deze browser.` });
    } else {
      setFileMessage({ kind: 'error', text: 'Opslaan in de browser lukt niet (opslag geblokkeerd of vol). Gebruik Download JSON.' });
    }
  };

  const loadSaved = (entry: SavedPlan) => {
    const result = parsePlanFile(entry.json, makeId);
    if (result.ok) applyLoadedPlan(result.plan, `"${entry.name}" geladen.`);
    else setFileMessage({ kind: 'error', text: result.error });
  };

  const deleteSaved = (entry: SavedPlan) => {
    if (!window.confirm(`"${entry.name}" uit deze browser verwijderen?`)) return;
    const list = saved.filter((s) => s.id !== entry.id);
    storeSavedPlans(list);
    setSaved(list);
  };

  const mapHint =
    tool === 'home'
      ? 'Klik op de plek waar de drone opstijgt en landt.'
      : tool === 'add'
        ? plan.mode === 'field'
          ? 'Klik de hoeken van het veld aan, rondom. Klaar? Druk op Esc.'
          : 'Klik de routepunten aan in vliegvolgorde. Klaar? Druk op Esc.'
        : planPoints(plan).length === 0
          ? 'Zoek je veld op (links bij Kaart) en klik op "Veldgrens tekenen".'
          : null;

  return (
    <div className="app">
      <aside className="sidebar">
        <header className="brand">
          <h1>Drone-routeplanner</h1>
          <p className="muted">Prototype voor een DJI Mavic Mini boven een gewasveld.</p>
          <p className="safety">Alleen planning. Deze app is niet verbonden met een drone en verstuurt geen vliegcommando's.</p>
          <div className="buttons buttons--small">
            <button type="button" disabled={history.past.length === 0 || simulating} onClick={() => dispatch({ type: 'undo' })}>
              Ongedaan maken
            </button>
            <button type="button" disabled={history.future.length === 0 || simulating} onClick={() => dispatch({ type: 'redo' })}>
              Opnieuw
            </button>
          </div>
        </header>

        <MapSourcePanel
          provider={provider}
          onProviderChange={(id) => {
            setProviderId(id);
            saveProviderId(id);
          }}
          onGoTo={(at) => focusOn([at])}
          onFitPlan={() => focusOn(planPoints(plan))}
          canFit={planPoints(plan).length > 0}
        />
        <DrawPanel
          plan={plan}
          analysis={analysis}
          tool={tool}
          selectedId={selectedId}
          disabled={simulating}
          onModeChange={changeMode}
          onToolChange={setTool}
          onSelect={(_, id, at) => {
            setSelectedId(id);
            focusOn([at]);
          }}
          onDelete={(target, id) => {
            dispatch({ type: 'deletePoint', target, id });
            if (id === selectedId) setSelectedId(null);
          }}
          onClear={(target) => dispatch({ type: 'clearPoints', target })}
          onCapture={(id, capture) => dispatch({ type: 'setCapture', id, capture })}
          onReverse={() => dispatch({ type: 'reverseRoute' })}
          onRemoveHome={() => dispatch({ type: 'setHome', at: null })}
          onUseGenerated={() => {
            dispatch({
              type: 'useGeneratedRoute',
              waypoints: analysis.route.waypoints,
              capture: analysis.route.legs.map((l) => l.capture),
            });
            setTool('none');
            setSelectedId(null);
          }}
        />
        <SettingsPanel
          plan={plan}
          analysis={analysis}
          disabled={simulating}
          onChange={(changes) => dispatch({ type: 'updateSettings', changes })}
        />
        <IssuesPanel issues={analysis.issues} />
        <EstimatePanel
          plan={plan}
          analysis={analysis}
          disabled={simulating}
          onAssumptionsChange={(changes) => dispatch({ type: 'updateAssumptions', changes })}
        />
        <SimulationPanel plan={plan} analysis={analysis} clock={clock} drone={drone} photosTaken={photosTaken} />
        <FilePanel
          name={plan.name}
          canExport={!analysis.hasErrors && !simulating}
          saved={saved}
          message={fileMessage}
          disabled={simulating}
          onNameChange={(name) => dispatch({ type: 'setName', name })}
          onDownload={download}
          onLoadFile={(file) => void loadFile(file)}
          onSaveInBrowser={saveInBrowser}
          onLoadSaved={loadSaved}
          onDeleteSaved={deleteSaved}
          onNewPlan={() => {
            dispatch({ type: 'replacePlan', plan: createEmptyPlan() });
            setSelectedId(null);
            setTool('none');
            setFileMessage({ kind: 'ok', text: 'Nieuw plan gestart. Met Ctrl+Z ga je terug.' });
          }}
        />
      </aside>

      <main className="map-wrap">
        <MapView
          plan={plan}
          analysis={analysis}
          provider={provider}
          tool={tool}
          selectedId={selectedId}
          drone={drone}
          photosTaken={photosTaken}
          simulating={simulating}
          focus={focus}
          onMapClick={onMapClick}
          onPointMove={(target, id, at) => dispatch({ type: 'movePoint', target, id, at })}
          onPointInsert={(target, index, at) => {
            dispatch({ type: 'insertPoint', target, index, at });
          }}
          onPointSelect={(_, id) => setSelectedId(id)}
          onHomeMove={(at) => dispatch({ type: 'setHome', at })}
          onDragStart={() => dispatch({ type: 'checkpoint' })}
        />
        {mapHint && !simulating && <div className="map-hint">{mapHint}</div>}
        {simulating && (
          <div className="sim-hud">
            <b>SIMULATIE</b> · {phaseLabel(drone)} · {formatDuration(clock.timeS)} · {formatNumber(drone?.altitudeM ?? 0)} m ·{' '}
            {formatNumber(photosTaken)} foto's
            <div className="sim-hud__note">Stop de simulatie om de route weer te bewerken.</div>
          </div>
        )}
      </main>
    </div>
  );
}
