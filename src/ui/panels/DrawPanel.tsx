import type { PlanAnalysis } from '../../core/analysis';
import { formatNumber } from '../../core/format';
import type { BoundaryPoint, LatLng, Plan, PlanMode, RoutePoint } from '../../core/types';
import type { Tool } from '../MapView';
import type { PointTarget } from '../planReducer';

interface Props {
  plan: Plan;
  analysis: PlanAnalysis;
  tool: Tool;
  selectedId: string | null;
  disabled: boolean;
  onModeChange(mode: PlanMode): void;
  onToolChange(tool: Tool): void;
  onSelect(target: PointTarget, id: string, at: LatLng): void;
  onDelete(target: PointTarget, id: string): void;
  onClear(target: PointTarget): void;
  onCapture(id: string, capture: boolean): void;
  onReverse(): void;
  onRemoveHome(): void;
  onUseGenerated(): void;
}

export function DrawPanel(props: Props) {
  const { plan, analysis, tool, disabled } = props;
  const field = plan.mode === 'field';
  const target: PointTarget = field ? 'boundary' : 'route';
  const points: (BoundaryPoint | RoutePoint)[] = field ? plan.boundary : plan.routePoints;

  return (
    <section className="panel">
      <h2>Tekenen</h2>
      <div className="tabs" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={field}
          className={field ? 'is-active' : ''}
          onClick={() => props.onModeChange('field')}
          disabled={disabled}
        >
          Veld + vliegbanen
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={!field}
          className={!field ? 'is-active' : ''}
          onClick={() => props.onModeChange('route')}
          disabled={disabled}
        >
          Eigen route
        </button>
      </div>

      <p className="help">
        {field
          ? 'Klik de hoeken van het veld aan. De planner legt er zelf evenwijdige vliegbanen in.'
          : 'Klik de routepunten in de volgorde waarin de drone moet vliegen.'}{' '}
        Sleep een punt om het te verplaatsen, klik op een <b>+</b> om er een tussen te voegen.
      </p>

      <div className="buttons">
        <button
          type="button"
          className={tool === 'add' ? 'is-active primary' : 'primary'}
          onClick={() => props.onToolChange(tool === 'add' ? 'none' : 'add')}
          disabled={disabled}
        >
          {tool === 'add' ? 'Klaar met klikken' : field ? 'Veldgrens tekenen' : 'Routepunten toevoegen'}
        </button>
        <button
          type="button"
          className={tool === 'home' ? 'is-active' : ''}
          onClick={() => props.onToolChange(tool === 'home' ? 'none' : 'home')}
          disabled={disabled}
        >
          {plan.home ? 'Startpunt verplaatsen' : 'Startpunt plaatsen'}
        </button>
      </div>

      {plan.home && (
        <div className="home-row">
          <span className="pt-inline pt-inline--home">H</span>
          <span className="coord">
            {plan.home.lat.toFixed(6)}, {plan.home.lng.toFixed(6)}
          </span>
          <button type="button" className="icon" onClick={props.onRemoveHome} disabled={disabled} aria-label="Startpunt verwijderen">
            ×
          </button>
        </div>
      )}

      <div className="list-head">
        <span>
          {field ? 'Grenspunten' : 'Routepunten'} ({points.length})
        </span>
        <span className="buttons buttons--small">
          {!field && points.length > 1 && (
            <button type="button" onClick={props.onReverse} disabled={disabled}>
              Omkeren
            </button>
          )}
          {points.length > 0 && (
            <button type="button" onClick={() => props.onClear(target)} disabled={disabled}>
              Alles wissen
            </button>
          )}
        </span>
      </div>
      {points.length === 0 ? (
        <p className="muted small">Nog geen punten.</p>
      ) : (
        <ol className="points">
          {points.map((p, i) => (
            <li
              key={p.id}
              className={p.id === props.selectedId ? 'is-selected' : ''}
              onClick={() => props.onSelect(target, p.id, p)}
            >
              <span className={`pt-inline pt-inline--${target}`}>{i + 1}</span>
              <span className="coord">
                {p.lat.toFixed(6)}, {p.lng.toFixed(6)}
              </span>
              {!field && i < points.length - 1 && (
                <label className="capture" title="Foto's maken op het stuk naar het volgende punt" onClick={(e) => e.stopPropagation()}>
                  <input
                    type="checkbox"
                    checked={(p as RoutePoint).capture}
                    disabled={disabled}
                    onChange={(e) => props.onCapture(p.id, e.target.checked)}
                  />
                  foto's
                </label>
              )}
              <button
                type="button"
                className="icon"
                aria-label={`Punt ${i + 1} verwijderen`}
                disabled={disabled}
                onClick={(e) => {
                  e.stopPropagation();
                  props.onDelete(target, p.id);
                }}
              >
                ×
              </button>
            </li>
          ))}
        </ol>
      )}
      <p className="muted small">Geselecteerd punt verwijderen: Delete-toets. Ongedaan maken: Ctrl+Z.</p>

      {field && analysis.route.lineCount > 0 && (
        <div className="generated">
          <div>
            Gegenereerd: <b>{analysis.route.lineCount}</b> vliegbanen, richting{' '}
            <b>{formatNumber(analysis.route.lineAngleDeg ?? 0)}°</b>, {analysis.route.waypoints.length} routepunten.
          </div>
          <button type="button" onClick={props.onUseGenerated} disabled={disabled}>
            Omzetten naar eigen route (punten los bewerken)
          </button>
        </div>
      )}
    </section>
  );
}
