import { useEffect, useId, useRef, useState } from 'react';
import { formatNumber } from '../core/format';

interface NumberFieldProps {
  label: string;
  unit: string;
  value: number;
  onChange(value: number): void;
  hint?: string;
  invalid?: boolean;
  disabled?: boolean;
}

function show(value: number): string {
  return Number.isFinite(value) ? formatNumber(value, value % 1 === 0 ? 0 : 2).replace(/\./g, '') : '';
}

/** Text input for numbers that accepts a Dutch comma and keeps half-typed values like "2,". */
export function NumberField({ label, unit, value, onChange, hint, invalid, disabled }: NumberFieldProps) {
  const id = useId();
  const [text, setText] = useState(() => show(value));
  const lastSent = useRef(value);

  useEffect(() => {
    // Only overwrite the text when the value changed from outside (load, undo).
    const same = value === lastSent.current || (Number.isNaN(value) && Number.isNaN(lastSent.current));
    if (!same) {
      lastSent.current = value;
      setText(show(value));
    }
  }, [value]);

  return (
    <div className={`field${invalid ? ' field--invalid' : ''}`}>
      <label htmlFor={id}>{label}</label>
      <div className="field__input">
        <input
          id={id}
          type="text"
          inputMode="decimal"
          value={text}
          disabled={disabled}
          aria-invalid={invalid || undefined}
          onChange={(e) => {
            const t = e.target.value;
            setText(t);
            const n = t.trim() === '' ? Number.NaN : Number(t.replace(',', '.'));
            lastSent.current = n;
            onChange(n);
          }}
        />
        <span className="field__unit">{unit}</span>
      </div>
      {hint && <div className="field__hint">{hint}</div>}
    </div>
  );
}
