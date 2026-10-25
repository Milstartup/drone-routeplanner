import type { PlanAnalysis } from '../../core/analysis';
import { formatNumber, formatPercent } from '../../core/format';
import type { FlightSettings, Plan } from '../../core/types';
import { NumberField } from '../NumberField';

interface Props {
  plan: Plan;
  analysis: PlanAnalysis;
  disabled: boolean;
  onChange(changes: Partial<FlightSettings>): void;
}

export function SettingsPanel({ plan, analysis, disabled, onChange }: Props) {
  const s = plan.settings;
  const field = plan.mode === 'field';
  const invalid = new Set(analysis.issues.filter((i) => i.level === 'error').map((i) => i.code));
  const { footprint, estimate } = analysis;
  const autoAngle = s.lineAngleDeg === null;

  return (
    <section className="panel">
      <h2>Instellingen</h2>
      <div className="grid2">
        <NumberField
          label="Vlieghoogte"
          unit="m"
          value={s.altitudeM}
          disabled={disabled}
          invalid={invalid.has('altitude-invalid') || invalid.has('altitude-low') || invalid.has('altitude-high')}
          onChange={(altitudeM) => onChange({ altitudeM })}
          hint="boven het startpunt"
        />
        <NumberField
          label="Snelheid"
          unit="m/s"
          value={s.speedMps}
          disabled={disabled}
          invalid={invalid.has('speed-invalid') || invalid.has('speed-high')}
          onChange={(speedMps) => onChange({ speedMps })}
          hint={Number.isFinite(s.speedMps) ? `${formatNumber(s.speedMps * 3.6, 1)} km/u` : undefined}
        />
        <NumberField
          label="Foto-interval"
          unit="s"
          value={s.photoIntervalS}
          disabled={disabled}
          invalid={invalid.has('interval-invalid') || invalid.has('interval-small')}
          onChange={(photoIntervalS) => onChange({ photoIntervalS })}
          hint={estimate.photoSpacingM > 0 ? `foto elke ${formatNumber(estimate.photoSpacingM, 1)} m` : undefined}
        />
        {field && (
          <NumberField
            label="Baanafstand"
            unit="m"
            value={s.lineSpacingM}
            disabled={disabled}
            invalid={invalid.has('spacing-invalid') || invalid.has('spacing-small')}
            onChange={(lineSpacingM) => onChange({ lineSpacingM })}
            hint="tussen twee vliegbanen"
          />
        )}
        {field && (
          <NumberField
            label="Randmarge"
            unit="m"
            value={s.edgeMarginM}
            disabled={disabled}
            invalid={invalid.has('margin-invalid')}
            onChange={(edgeMarginM) => onChange({ edgeMarginM })}
            hint="afstand banen tot de grens"
          />
        )}
        {field && (
          <div className="field">
            <label htmlFor="angle-mode">Baanrichting</label>
            <select
              id="angle-mode"
              value={autoAngle ? 'auto' : 'manual'}
              disabled={disabled}
              onChange={(e) =>
                onChange({
                  lineAngleDeg: e.target.value === 'auto' ? null : Math.round(analysis.route.lineAngleDeg ?? 0),
                })
              }
            >
              <option value="auto">Automatisch</option>
              <option value="manual">Zelf kiezen</option>
            </select>
            {autoAngle && analysis.route.lineAngleDeg !== null && (
              <div className="field__hint">langste zijde: {formatNumber(analysis.route.lineAngleDeg)}° (0° = noord-zuid)</div>
            )}
          </div>
        )}
        {field && !autoAngle && (
          <NumberField
            label="Richting"
            unit="°"
            value={s.lineAngleDeg ?? 0}
            disabled={disabled}
            invalid={invalid.has('angle-invalid')}
            onChange={(lineAngleDeg) => onChange({ lineAngleDeg })}
            hint="0° = noord-zuid, 90° = oost-west"
          />
        )}
      </div>

      {footprint && (
        <div className="info">
          Eén foto dekt op {formatNumber(s.altitudeM)} m ongeveer <b>{formatNumber(footprint.widthM)} × {formatNumber(footprint.lengthM)} m</b>{' '}
          ({formatNumber(footprint.gsdCm, 1)} cm per pixel).
          {estimate.frontOverlap !== null && (
            <>
              {' '}
              Overlap voor-achter: <b>{formatPercent(Math.max(0, estimate.frontOverlap))}</b>
            </>
          )}
          {estimate.sideOverlap !== null && (
            <>
              , zijkant: <b>{formatPercent(Math.max(0, estimate.sideOverlap))}</b>
            </>
          )}
          .
        </div>
      )}
    </section>
  );
}
