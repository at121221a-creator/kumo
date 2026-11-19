import { useEffect, useRef, useState } from 'react';
import './style.css';
import { t } from './i18n.js';

const KEY = 'pomodoro.v1';
const MODES = ['focus', 'short', 'long'];
const DEFAULTS = { focus: 25, short: 5, long: 15, every: 4 };
const LIMITS = { focus: [5, 90], short: [1, 30], long: [5, 60], every: [2, 8] };

const todayKey = () => new Date().toDateString();

/// Everything is kept as it changes: the user may leave at any moment. A running timer is kept as
/// the time it ends, so it is right again after the page was closed or put away.
function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY));
    if (saved && saved.lengths) return saved;
  } catch {}
  return { lengths: DEFAULTS, mode: 'focus', endsAt: null, left: DEFAULTS.focus * 60, streak: 0, day: todayKey(), done: 0 };
}

const clock = (seconds) => `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;

/// A soft two-note chime. iOS only lets a page play sound once a tap has started its audio.
let audio;
function unlock() {
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    if (audio.state === 'suspended') audio.resume();
  } catch {}
}
function chime() {
  if (!audio) return;
  [[880, 0], [1320, 0.18]].forEach(([frequency, delay]) => {
    const start = audio.currentTime + delay;
    const tone = audio.createOscillator();
    const gain = audio.createGain();
    tone.type = 'sine';
    tone.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.3, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + 1.1);
    tone.connect(gain).connect(audio.destination);
    tone.start(start);
    tone.stop(start + 1.2);
  });
}

export default function App() {
  const [state, setState] = useState(load);
  const [now, setNow] = useState(Date.now());
  const [message, setMessage] = useState('');
  const [tuning, setTuning] = useState(false);
  const finishing = useRef(false);

  // A new day starts the count again.
  const done = state.day === todayKey() ? state.done : 0;
  const running = state.endsAt != null;
  const total = state.lengths[state.mode] * 60;
  const left = running ? Math.max(0, Math.ceil((state.endsAt - now) / 1000)) : state.left;
  const progress = 1 - left / total;

  useEffect(() => {
    localStorage.setItem(KEY, JSON.stringify(state));
  }, [state]);

  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => setNow(Date.now()), 250);
    const back = () => setNow(Date.now());
    document.addEventListener('visibilitychange', back);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', back);
    };
  }, [running]);

  // Time is up: count the session, chime, and line up what comes next, paused.
  useEffect(() => {
    if (!running || left > 0 || finishing.current) return;
    finishing.current = true;
    chime();
    setMessage(t.done[state.mode]);
    setState((s) => {
      const day = todayKey();
      const doneToday = s.day === day ? s.done : 0;
      if (s.mode === 'focus') {
        const streak = s.streak + 1;
        const next = streak % s.lengths.every === 0 ? 'long' : 'short';
        return { ...s, mode: next, endsAt: null, left: s.lengths[next] * 60, streak, day, done: doneToday + 1 };
      }
      return { ...s, mode: 'focus', endsAt: null, left: s.lengths.focus * 60, day, done: doneToday };
    });
  }, [running, left, state.mode]);

  useEffect(() => {
    if (running) finishing.current = false;
  }, [running]);

  useEffect(() => {
    if (!message) return;
    const timer = setTimeout(() => setMessage(''), 6000);
    return () => clearTimeout(timer);
  }, [message]);

  const toggle = () => {
    unlock();
    setMessage('');
    setNow(Date.now());
    setState((s) => (s.endsAt != null
      ? { ...s, endsAt: null, left: Math.max(0, Math.ceil((s.endsAt - Date.now()) / 1000)) }
      : { ...s, endsAt: Date.now() + s.left * 1000 }));
  };
  const pick = (mode) => setState((s) => ({ ...s, mode, endsAt: null, left: s.lengths[mode] * 60 }));
  const reset = () => setState((s) => ({ ...s, endsAt: null, left: s.lengths[s.mode] * 60 }));
  const skip = () => {
    unlock();
    setState((s) => ({ ...s, endsAt: Date.now() - 1 }));
    setNow(Date.now());
  };
  const tune = (key, delta) => setState((s) => {
    const [min, max] = LIMITS[key];
    const lengths = { ...s.lengths, [key]: Math.min(max, Math.max(min, s.lengths[key] + delta)) };
    // The timer on screen follows a new length, unless it is running.
    const left = s.endsAt == null && key === s.mode ? lengths[key] * 60 : s.left;
    return { ...s, lengths, left };
  });

  const size = 280;
  const stroke = 14;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const paused = !running && left < total;

  return (
    <main className={`page mode-${state.mode}`}>
      <div className="modes" role="tablist">
        {MODES.map((mode) => (
          <button key={mode} role="tab" aria-selected={mode === state.mode} className={mode === state.mode ? 'on' : ''} onClick={() => pick(mode)}>
            {t.modes[mode]}
          </button>
        ))}
      </div>

      <section className="dial" aria-live="off">
        <svg viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
          <circle className="track" cx={size / 2} cy={size / 2} r={radius} strokeWidth={stroke} />
          <circle
            className="fill"
            cx={size / 2}
            cy={size / 2}
            r={radius}
            strokeWidth={stroke}
            strokeDasharray={circumference}
            strokeDashoffset={circumference * (1 - progress)}
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
          />
        </svg>
        <div className="readout">
          <span className="label">{state.mode === 'focus' ? t.round(state.streak + 1) : t.breakTime}</span>
          <span className="time" role="timer">{clock(left)}</span>
        </div>
      </section>

      <p className={`message${message ? ' shown' : ''}`} role="status">{message || ' '}</p>

      <div className="controls">
        <button className="round" onClick={reset} aria-label={t.reset}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v4.5h4.5" /></svg>
        </button>
        <button className="main" onClick={toggle}>
          {running ? (
            <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="5" width="3.6" height="14" rx="1.2" /><rect x="13.9" y="5" width="3.6" height="14" rx="1.2" /></svg>
          ) : (
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.6v12.8a1 1 0 0 0 1.5.9l10.2-6.4a1 1 0 0 0 0-1.8L9.5 4.7A1 1 0 0 0 8 5.6z" /></svg>
          )}
          <span>{running ? t.pause : paused ? t.resume : t.start}</span>
        </button>
        <button className="round" onClick={skip} aria-label={t.skip}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 6l8 6-8 6zM17 6v12" /></svg>
        </button>
      </div>

      <section className="card">
        <div className="tally">
          <span>{t.today}</span>
          <span className="tomatoes" aria-label={t.count(done)}>
            {done === 0 ? <span className="none">0</span> : Array.from({ length: Math.min(done, 12) }, (_, i) => <span key={i}>🍅</span>)}
            {done > 12 && <span className="more">+{done - 12}</span>}
          </span>
        </div>
        <button className="tune" onClick={() => setTuning((v) => !v)} aria-expanded={tuning}>
          <span>{t.lengths}</span>
          <span className="summary">
            {state.lengths.focus} · {state.lengths.short} · {state.lengths.long} {t.minutes}
            <svg viewBox="0 0 24 24" aria-hidden="true" className={tuning ? 'open' : ''}><path d="M9 6l6 6-6 6" /></svg>
          </span>
        </button>
        {tuning && (
          <div className="steppers">
            {MODES.map((mode) => (
              <Stepper key={mode} label={t.modes[mode]} value={state.lengths[mode]} unit={t.minutes} step={mode === 'focus' ? 5 : 1}
                onChange={(delta) => tune(mode, delta)} />
            ))}
            <Stepper label={t.every} value={state.lengths.every} unit={t.everyUnit} step={1} onChange={(delta) => tune('every', delta)} />
          </div>
        )}
      </section>

      <p className="note">{t.note}</p>
    </main>
  );
}

function Stepper({ label, value, unit, step, onChange }) {
  return (
    <div className="stepper">
      <span>{label}</span>
      <span className="stepper-value">{value} <small>{unit}</small></span>
      <span className="stepper-buttons">
        <button onClick={() => onChange(-step)} aria-label="−">−</button>
        <button onClick={() => onChange(step)} aria-label="+">+</button>
      </span>
    </div>
  );
}
