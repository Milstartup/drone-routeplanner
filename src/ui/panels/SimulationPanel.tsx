import type { PlanAnalysis } from '../../core/analysis';
import { formatDuration, formatNumber, formatPercent } from '../../core/format';
import type { DroneState } from '../../core/timeline';
import type { Plan } from '../../core/types';
import type { SimulationClock } from '../useSimulation';

const RATES = [1, 2, 5, 10, 20, 50];

export function phaseLabel(state: DroneState | null): string {
  if (!state) return 'Klaar om te starten';
  switch (state.phase) {
    case 'climb':
      return 'Opstijgen';
    case 'fly':
      return state.capture ? "Vliegbaan, foto's maken" : "Overvliegen, geen foto's";
    case 'pause':
      return 'Afremmen en draaien';
    case 'descend':
      return 'Landen';
    case 'done':
      return 'Klaar';
  }
}

interface Props {
  plan: Plan;
  analysis: PlanAnalysis;
  clock: SimulationClock;
  drone: DroneState | null;
  photosTaken: number;
}

export function SimulationPanel({ plan, analysis, clock, drone, photosTaken }: Props) {
  const total = analysis.timeline.totalS;
  const blocked = analysis.hasErrors || total <= 0;
  const started = clock.timeS > 0;
  const usable = plan.assumptions.usableFlightTimeS;

  return (
    <section className="panel">
      <h2>Simulatie</h2>
      <p className="help">Een animatie van de geplande vlucht in de browser. Er wordt niets naar een drone gestuurd.</p>
      <div className="buttons">
        <button type="button" className="primary" disabled={blocked} onClick={clock.playing ? clock.pause : clock.play}>
          {clock.playing ? 'Pauze' : started && clock.timeS < total ? 'Verder' : 'Start simulatie'}
        </button>
        <button type="button" disabled={!started} onClick={clock.reset}>
          Stop
        </button>
        <label className="inline">
          Tempo{' '}
          <select value={clock.rate} onChange={(e) => clock.setRate(Number(e.target.value))}>
            {RATES.map((r) => (
              <option key={r} value={r}>
                {r}×
              </option>
            ))}
          </select>
        </label>
      </div>
      <input
        type="range"
        className="scrub"
        min={0}
        max={Math.max(total, 0.1)}
        step={0.1}
        value={clock.timeS}
        disabled={blocked}
        onChange={(e) => clock.seek(Number(e.target.value))}
        aria-label="Tijd in de simulatie"
      />
      {blocked && analysis.hasErrors && <p className="muted small">Eerst de fouten oplossen (zie Controle).</p>}
      {!blocked && (
        <table className="stats">
          <tbody>
            <tr>
              <th>Tijd</th>
              <td>
                {formatDuration(clock.timeS)} / {formatDuration(total)}
              </td>
            </tr>
            <tr>
              <th>Fase</th>
              <td>{phaseLabel(started ? drone : null)}</td>
            </tr>
            <tr>
              <th>Hoogte</th>
              <td>{drone ? `${formatNumber(drone.altitudeM)} m` : '–'}</td>
            </tr>
            <tr>
              <th>Foto's gemaakt</th>
              <td>
                {formatNumber(photosTaken)} / {formatNumber(analysis.photos.length)}
              </td>
            </tr>
            <tr>
              <th>Accu gebruikt (schatting)</th>
              <td>{usable > 0 ? formatPercent(clock.timeS / usable) : '–'}</td>
            </tr>
          </tbody>
        </table>
      )}
    </section>
  );
}
