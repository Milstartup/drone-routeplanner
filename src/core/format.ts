// Dutch number formatting for the UI and for messages.

export function formatNumber(n: number, decimals = 0): string {
  return n.toLocaleString('nl-NL', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

/** 125 s -> "2:05"; 3725 s -> "1:02:05". */
export function formatDuration(totalS: number): string {
  const s = Math.max(0, Math.round(totalS));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
}

export function formatDistance(m: number): string {
  return m >= 1000 ? `${formatNumber(m / 1000, 2)} km` : `${formatNumber(m)} m`;
}

export function formatArea(m2: number): string {
  return m2 >= 10000 ? `${formatNumber(m2 / 10000, 2)} ha` : `${formatNumber(m2)} m²`;
}

export function formatPercent(fraction: number): string {
  return `${formatNumber(fraction * 100)}%`;
}
