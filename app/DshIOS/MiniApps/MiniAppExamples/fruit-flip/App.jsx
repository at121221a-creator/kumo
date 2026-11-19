import { useEffect, useRef, useState } from 'react';
import './style.css';
import { t } from './i18n.js';

const FRUIT = ['🍎', '🍊', '🍋', '🍉', '🍇', '🍓', '🍑', '🍍', '🥝', '🍌', '🥥', '🍒'];
// Columns and rows: every level is an even number of cards.
const LEVELS = [[3, 4], [4, 4], [4, 5]];
const BEST_KEY = 'fruit-flip.best';
const LEVEL_KEY = 'fruit-flip.level';

function deal(level) {
  const [cols, rows] = LEVELS[level];
  const pairs = (cols * rows) / 2;
  const fruit = [...FRUIT].sort(() => Math.random() - 0.5).slice(0, pairs);
  const cards = [...fruit, ...fruit].map((face, index) => ({ id: index, face, matched: false }));
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

const read = (key, fallback) => {
  try {
    const value = JSON.parse(localStorage.getItem(key));
    return value ?? fallback;
  } catch {
    return fallback;
  }
};

const clock = (seconds) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

/// Three stars for close to perfect play, fewer as moves pile up.
const stars = (moves, pairs) => (moves <= pairs * 1.5 ? 3 : moves <= pairs * 2.2 ? 2 : 1);

export default function App() {
  const [level, setLevel] = useState(() => read(LEVEL_KEY, 0));
  const [cards, setCards] = useState(() => deal(read(LEVEL_KEY, 0)));
  const [open, setShown] = useState([]);
  // Two quick taps land before a render: the second must see the first.
  const openRef = useRef([]);
  const setOpen = (cards) => {
    openRef.current = cards;
    setShown(cards);
  };
  const [moves, setMoves] = useState(0);
  const [started, setStarted] = useState(null);
  const [now, setNow] = useState(Date.now());
  const [best, setBest] = useState(() => read(BEST_KEY, {}));
  const [result, setResult] = useState(null);
  const busy = useRef(false);

  const [cols, rows] = LEVELS[level];
  const pairs = cards.length / 2;
  const seconds = started ? Math.floor(((result ? result.at : now) - started) / 1000) : 0;

  useEffect(() => {
    if (!started || result) return;
    const timer = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(timer);
  }, [started, result]);

  const start = (next = level) => {
    setLevel(next);
    localStorage.setItem(LEVEL_KEY, JSON.stringify(next));
    setCards(deal(next));
    setOpen([]);
    setMoves(0);
    setStarted(null);
    setResult(null);
    busy.current = false;
  };

  const flip = (index) => {
    const current = openRef.current;
    if (busy.current || current.includes(index) || cards[index].matched) return;
    if (!started) {
      setStarted(Date.now());
      setNow(Date.now());
    }
    const next = [...current, index];
    setOpen(next);
    if (next.length < 2) return;

    setMoves((count) => count + 1);
    const [a, b] = next;
    busy.current = true;
    if (cards[a].face === cards[b].face) {
      setTimeout(() => {
        const updated = cards.map((card, i) => (i === a || i === b ? { ...card, matched: true } : card));
        setCards(updated);
        setOpen([]);
        busy.current = false;
        if (updated.every((card) => card.matched)) finish(moves + 1);
      }, 320);
    } else {
      setTimeout(() => {
        setOpen([]);
        busy.current = false;
      }, 800);
    }
  };

  const finish = (total) => {
    const at = Date.now();
    const time = Math.floor((at - (started || at)) / 1000);
    const previous = best[level];
    const record = !previous || total < previous.moves || (total === previous.moves && time < previous.time);
    if (record) {
      const updated = { ...best, [level]: { moves: total, time } };
      setBest(updated);
      localStorage.setItem(BEST_KEY, JSON.stringify(updated));
    }
    setResult({ at, moves: total, time, record });
  };

  const record = best[level];

  return (
    <main className="stand">
      <div className="levels" role="tablist">
        {t.levels.map((name, index) => (
          <button key={name} role="tab" aria-selected={index === level} className={index === level ? 'on' : ''} onClick={() => start(index)}>
            {name}
          </button>
        ))}
      </div>

      <dl className="score">
        <div><dt>{t.moves}</dt><dd>{moves}</dd></div>
        <div><dt>{t.time}</dt><dd>{clock(seconds)}</dd></div>
        <div><dt>{t.best}</dt><dd>{record ? record.moves : '–'}</dd></div>
      </dl>

      <div className="board" style={{ '--cols': cols, '--rows': rows }}>
        {cards.map((card, index) => {
          const up = card.matched || open.includes(index);
          return (
            <button
              key={card.id}
              className={`card${up ? ' up' : ''}${card.matched ? ' matched' : ''}`}
              onClick={() => flip(index)}
              aria-label={up ? card.face : t.hidden}
            >
              <span className="card-inner">
                <span className="card-back" aria-hidden="true" />
                <span className="card-face" aria-hidden="true">{card.face}</span>
              </span>
            </button>
          );
        })}
      </div>

      <p className="hint">{started ? '' : t.hint}</p>

      <button className="restart" onClick={() => start()}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v4.5h4.5" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none" /></svg>
        {t.restart}
      </button>

      {result && (
        <div className="won" role="dialog" aria-label={t.won}>
          <div className="won-card">
            <div className="stars" aria-label={`${stars(result.moves, pairs)}/3`}>
              {[1, 2, 3].map((n) => (
                <span key={n} className={n <= stars(result.moves, pairs) ? 'lit' : ''}>★</span>
              ))}
            </div>
            <h2>{t.won}</h2>
            <p className="won-line">
              {t.moves} {result.moves}　{t.time} {clock(result.time)}
            </p>
            {result.record && <p className="won-best">{t.newBest}</p>}
            <button className="again" onClick={() => start()}>{t.again}</button>
          </div>
        </div>
      )}
    </main>
  );
}
