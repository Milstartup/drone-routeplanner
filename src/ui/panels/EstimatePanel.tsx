import type { PlanAnalysis } from '../../core/analysis';
import { formatArea, formatDistance, formatDuration, formatNumber, formatPercent } from '../../core/format';
import { MAVIC_MINI } from '../../core/mavicMini';
import type { Assumptions, Plan } from '../../core/types';
import { NumberField } from '../NumberField';

interface Props {
  plan: Plan;
  analysis: PlanAnalysis;
  disabled: boolean;
  onAssumptionsChange(changes: Partial<Assumptions>): void;
}

export function EstimatePanel({ plan, analysis, disabled, onAssumptionsChange }: Props) {
  const e = analysis.estimate;
  const a = plan.assumptions;
  const battery = e.batteryFraction;
  const batteryClass = battery > 1 ? 'bar--bad' : battery > 0.85 ? 'bar--warn' : 'bar--ok';
  const empty = analysis.route.waypoints.length === 0;

  return (
    <section className="panel">
      <h2>Schatting</h2>
      {empty ? (
        <p className="muted small">Nog geen route om te schatten.</p>
      ) : (
        <>
          <table className="stats">
            <tbody>
              <tr>
                <th>Routelengte</th>
                <td>{formatDistance(e.totalDistanceM)}</td>
              </tr>
              <tr className="sub">
                <th>waarvan met foto's</th>
                <td>{formatDistance(e.photoDistanceM)}</td>
              </tr>
              <tr className="sub">
                <th>overgangen zonder foto's</th>
                <td>{formatDistance(e.transitDistanceM)}</td>
              </tr>
              <tr className="sub">
                <th>van en naar startpunt</th>
                <td>{plan.home ? formatDistance(e.homeDistanceM) : 'geen startpunt'}</td>
              </tr>
              <tr>
                <th>Vliegtijd</th>
                <td>
                  <b>{formatDuration(e.totalS)}</b> min
                </td>
              </tr>
              <tr className="sub">
                <th>opstijgen + landen</th>
                <td>{formatDuration(e.climbS + e.descentS)}</td>
              </tr>
              <tr className="sub">
                <th>vliegen</th>
                <td>{formatDuration(e.flyS)}</td>
              </tr>
              <tr className="sub">
                <th>afremmen en draaien</th>
                <td>{formatDuration(e.pauseS)}</td>
              </tr>
              <tr>
                <th>Aantal foto's</th>
                <td>
                  <b>{formatNumber(e.photoCount)}</b>
                </td>
              </tr>
              <tr>
                <th>Routepunten</th>
                <td>{formatNumber(e.waypointCount)}</td>
              </tr>
              {e.fieldAreaM2 !== null && (
                <tr>
                  <th>Veldoppervlak</th>
                  <td>{formatArea(e.fieldAreaM2)}</td>
                </tr>
              )}
            </tbody>
          </table>
          <div className="battery">
            <div className="battery__label">
              Accu: {formatPercent(battery)} van {formatDuration(a.usableFlightTimeS)} min bruikbare vliegtijd
            </div>
            <div className={`bar ${batteryClass}`}>
              <div style={{ width: `${Math.min(100, battery * 100)}%` }} />
            </div>
          </div>
        </>
      )}

      <details className="assumptions">
        <summary>Aannames achter deze schatting</summary>
        <ul>
          <li>Constante snelheid langs de route, zonder wind. Wind en kou maken de vlucht in het echt langer en de accu sneller leeg.</li>
          <li>Bij elk routepunt een vaste pauze voor afremmen, draaien en optrekken (hieronder in te stellen).</li>
          <li>Opstijgen recht omhoog bij het startpunt, rechtstreeks naar het eerste punt, na het laatste punt terug naar het startpunt en recht omlaag landen.</li>
          <li>Hoogte is ten opzichte van het startpunt; het veld wordt als vlak aangenomen.</li>
          <li>
            Foto's op vaste afstand (snelheid × interval) langs de stukken met foto's. Elke vliegbaan begint met een foto; in bochten en
            overgangen worden geen foto's gemaakt.
          </li>
          <li>
            Camera recht naar beneden, lange kant van de foto dwars op de vliegrichting. Mavic Mini: {MAVIC_MINI.camera.sensor}, diagonale
            beeldhoek {MAVIC_MINI.camera.diagonalFovDeg}°, foto {MAVIC_MINI.camera.imageWidthPx} × {MAVIC_MINI.camera.imageHeightPx} (4:3).
          </li>
          <li>
            De Mavic Mini haalt volgens DJI maximaal {MAVIC_MINI.maxFlightTimeMin} minuten (windstil, 14 km/u). De bruikbare tijd hieronder is
            bewust lager, voor reserve en de terugweg.
          </li>
          <li>Afstanden over het aardoppervlak; velden worden in een platte kaartprojectie berekend (nauwkeurig binnen enkele kilometers).</li>
        </ul>
        <div className="grid2">
          <NumberField
            label="Stijgsnelheid"
            unit="m/s"
            value={a.ascentSpeedMps}
            disabled={disabled}
            onChange={(ascentSpeedMps) => onAssumptionsChange({ ascentSpeedMps })}
          />
          <NumberField
            label="Daalsnelheid"
            unit="m/s"
            value={a.descentSpeedMps}
            disabled={disabled}
            onChange={(descentSpeedMps) => onAssumptionsChange({ descentSpeedMps })}
          />
          <NumberField
            label="Pauze per routepunt"
            unit="s"
            value={a.waypointPauseS}
            disabled={disabled}
            onChange={(waypointPauseS) => onAssumptionsChange({ waypointPauseS })}
          />
          <NumberField
            label="Bruikbare vliegtijd"
            unit="min"
            value={a.usableFlightTimeS / 60}
            disabled={disabled}
            onChange={(min) => onAssumptionsChange({ usableFlightTimeS: min * 60 })}
          />
          <NumberField
            label="Max. afstand (zicht)"
            unit="m"
            value={a.maxDistanceFromHomeM}
            disabled={disabled}
            onChange={(maxDistanceFromHomeM) => onAssumptionsChange({ maxDistanceFromHomeM })}
          />
        </div>
      </details>
    </section>
  );
}
