import type { Issue } from '../../core/validate';

export function IssuesPanel({ issues }: { issues: Issue[] }) {
  const errors = issues.filter((i) => i.level === 'error');
  const warnings = issues.filter((i) => i.level === 'warning');
  return (
    <section className="panel">
      <h2>
        Controle{' '}
        {errors.length > 0 ? (
          <span className="badge badge--error">{errors.length} fout</span>
        ) : (
          <span className="badge badge--ok">geen fouten</span>
        )}
        {warnings.length > 0 && <span className="badge badge--warn">{warnings.length} let op</span>}
      </h2>
      {issues.length === 0 ? (
        <p className="muted small">Geen problemen gevonden.</p>
      ) : (
        <ul className="issues">
          {[...errors, ...warnings].map((i, n) => (
            <li key={`${i.code}-${n}`} className={`issue issue--${i.level}`}>
              <span className="issue__tag">{i.level === 'error' ? 'Fout' : 'Let op'}</span>
              {i.message}
            </li>
          ))}
        </ul>
      )}
      {errors.length > 0 && <p className="muted small">Los de fouten op om te simuleren of de route als JSON op te slaan.</p>}
    </section>
  );
}
