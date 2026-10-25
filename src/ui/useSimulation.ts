// Simulation clock. It only moves a time value forward; positions come from the core timeline.
// Nothing here talks to a drone.
import { useCallback, useEffect, useRef, useState } from 'react';

export interface SimulationClock {
  timeS: number;
  playing: boolean;
  rate: number;
  play(): void;
  pause(): void;
  reset(): void;
  seek(t: number): void;
  setRate(rate: number): void;
}

/** `resetKey` changes whenever the plan changes; the clock then goes back to the start. */
export function useSimulation(totalS: number, resetKey: unknown): SimulationClock {
  const [timeS, setTimeS] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [rate, setRate] = useState(10);
  const timeRef = useRef(0);

  useEffect(() => {
    timeRef.current = 0;
    setTimeS(0);
    setPlaying(false);
  }, [resetKey]);

  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = Math.min(0.25, (now - last) / 1000);
      last = now;
      const next = Math.min(totalS, timeRef.current + dt * rate);
      timeRef.current = next;
      setTimeS(next);
      if (next >= totalS) {
        setPlaying(false);
        return;
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing, rate, totalS]);

  const play = useCallback(() => {
    if (timeRef.current >= totalS) {
      timeRef.current = 0;
      setTimeS(0);
    }
    if (totalS > 0) setPlaying(true);
  }, [totalS]);
  const pause = useCallback(() => setPlaying(false), []);
  const reset = useCallback(() => {
    setPlaying(false);
    timeRef.current = 0;
    setTimeS(0);
  }, []);
  const seek = useCallback(
    (t: number) => {
      const clamped = Math.max(0, Math.min(totalS, t));
      timeRef.current = clamped;
      setTimeS(clamped);
    },
    [totalS],
  );

  return { timeS, playing, rate, play, pause, reset, seek, setRate };
}
