import React, { useEffect, useRef, useState, useCallback } from 'react';

const GIFS = ['/fitingo_wo_pushups.gif', '/fitingo_workout.gif', '/fitingo_wo_squat.gif'];
const TIPS = [
  '💡 たった5回から始めよう！',
  '⚡ 90秒で体が変わる！',
  '🎯 まず始めることが大切！',
  '🔥 毎日続けると体が軽くなる！',
  '🌟 Fitiongoと一緒に頑張ろう！',
  '💪 小さな積み重ねが大きな変化！',
];
const NS90_KEY = 'ns90.activeDates';
const MAX_DAYS = 7;

/** 今日 YYYY-MM-DD */
const todayStr = () => new Date().toISOString().slice(0, 10);

function getActiveDays(): string[] {
  try {
    const raw = localStorage.getItem(NS90_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function recordToday(): string[] {
  const today = todayStr();
  const days = getActiveDays();
  if (!days.includes(today)) {
    const next = [...days, today].slice(-MAX_DAYS);
    localStorage.setItem(NS90_KEY, JSON.stringify(next));
    return next;
  }
  return days;
}

interface Props {
  onStart: () => void;   // スタートボタン → ワークアウト開始
  onExit: () => void;    // すべての機能を見る → ダッシュボード/ログイン
  doneToday?: boolean;   // 今日すでに完了済み
}

export const NinetySecondMode: React.FC<Props> = ({ onStart, onExit, doneToday = false }) => {
  const [gifIdx, setGifIdx] = useState(0);
  const [tipIdx, setTipIdx] = useState(0);
  const [activeDays, setActiveDays] = useState<string[]>(getActiveDays);
  const [pulse, setPulse] = useState(false);
  const gifTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const tipTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const graduated = activeDays.length >= MAX_DAYS;
  const accentColor = doneToday ? '#1CB0F6' : '#58CC02';
  const accentLight = doneToday ? 'rgba(28,176,246,0.12)' : 'rgba(88,204,2,0.12)';

  // GIF ローテーション（10秒ごと）
  useEffect(() => {
    gifTimerRef.current = setInterval(() => {
      setGifIdx((i) => (i + 1) % GIFS.length);
    }, 10_000);
    return () => { if (gifTimerRef.current) clearInterval(gifTimerRef.current); };
  }, []);

  // Tip ローテーション（4秒ごと）
  useEffect(() => {
    tipTimerRef.current = setInterval(() => {
      setTipIdx((i) => (i + 1) % TIPS.length);
    }, 4_000);
    return () => { if (tipTimerRef.current) clearInterval(tipTimerRef.current); };
  }, []);

  // ボタンパルス
  useEffect(() => {
    const t = setInterval(() => setPulse((p) => !p), 1600);
    return () => clearInterval(t);
  }, []);

  const handleStart = useCallback(() => {
    const updated = recordToday();
    setActiveDays(updated);
    onStart();
  }, [onStart]);

  return (
    <div
      className="min-h-screen flex flex-col items-center"
      style={{
        background: doneToday
          ? 'linear-gradient(180deg, #E8F4FF 0%, #fff 100%)'
          : 'linear-gradient(180deg, #F0FFF4 0%, #fff 100%)',
      }}
    >
      {/* ── ストリーク（簡易表示） ─────────────────────────────── */}
      <div className="mt-6 flex items-center gap-1.5">
        <span className="text-2xl">🔥</span>
        <span className="text-base font-black text-duo-dark">{activeDays.length}日連続</span>
      </div>

      {/* ── GIF（スクワット以外優先・タップで切替） ─────────────── */}
      <div
        className="relative mt-4 mx-6 cursor-pointer overflow-hidden rounded-2xl shadow-md"
        style={{ width: 'calc(100% - 48px)', maxWidth: 400, height: 148 }}
        onClick={() => setGifIdx((i) => (i + 1) % GIFS.length)}
      >
        <img
          key={gifIdx}
          src={GIFS[gifIdx]}
          alt="exercise"
          className="w-full h-full object-cover"
          style={{ display: 'block' }}
        />
        {/* 切替ヒント */}
        <div className="absolute bottom-2 right-2 rounded-full bg-white/70 p-1">
          <span className="text-xs" style={{ color: accentColor }}>▶</span>
        </div>
      </div>

      {/* ── 大きなタグライン ──────────────────────────────────── */}
      <p
        className="mt-5 text-4xl font-black tracking-tight text-center"
        style={{ color: accentColor, textShadow: `0 2px 8px ${accentColor}33` }}
      >
        今度こそ、続く。
      </p>

      {/* ── メインスタートボタン ──────────────────────────────── */}
      <button
        onClick={handleStart}
        style={{
          marginTop: 24,
          width: 180,
          height: 180,
          borderRadius: '50%',
          background: accentColor,
          boxShadow: `0 8px 0 ${doneToday ? '#1090CC' : '#46A302'}, 0 0 ${pulse ? 32 : 16}px ${accentColor}66`,
          transform: `scale(${pulse ? 1.04 : 1.0})`,
          transition: 'transform 1.6s ease-in-out, box-shadow 1.6s ease-in-out',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 6,
          border: 'none',
          cursor: 'pointer',
        }}
      >
        <img
          src="/mascot.png"
          alt="Fitingo"
          style={{ width: 72, height: 72, borderRadius: '50%', objectFit: 'cover' }}
        />
        <span style={{ color: '#fff', fontWeight: 900, fontSize: 18 }}>
          {doneToday ? '今日は完了！' : '今日の90秒'}
        </span>
      </button>

      {/* ── ボタン下サブテキスト ──────────────────────────────── */}
      <p className="mt-3 text-sm font-semibold text-duo-gray">
        {doneToday ? 'もう1セットやる ▶' : '今日の90秒、それだけ'}
      </p>

      {/* ── Fitiongo からの一言 ───────────────────────────────── */}
      <div className="mt-5 flex items-center gap-2 px-6">
        <img
          src="/mascot.png"
          alt="Fitingo"
          style={{ width: 26, height: 26, borderRadius: '50%', objectFit: 'cover' }}
        />
        <p
          key={tipIdx}
          className="text-sm font-semibold text-duo-gray transition-opacity duration-300"
        >
          {TIPS[tipIdx]}
        </p>
      </div>

      {/* ── 7日進捗ドット ─────────────────────────────────────── */}
      <div className="mt-6 flex flex-col items-center gap-2">
        <div className="flex gap-2.5">
          {Array.from({ length: MAX_DAYS }).map((_, i) => (
            <div
              key={i}
              style={{
                width: 14, height: 14, borderRadius: '50%',
                background: i < activeDays.length ? '#58CC02' : '#e5e5e5',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
            >
              {i < activeDays.length && (
                <span style={{ color: '#fff', fontSize: 8, fontWeight: 900, lineHeight: 1 }}>✓</span>
              )}
            </div>
          ))}
        </div>
        <p className="text-xs font-bold" style={{ color: graduated ? '#FF9600' : '#afafaf' }}>
          {graduated
            ? '🎉 7日続きました！全機能が開放されています！'
            : `あと${MAX_DAYS - activeDays.length}日で全機能が開放`}
        </p>
      </div>

      {/* ── 全機能ボタン（卒業時） ────────────────────────────── */}
      {graduated && (
        <button
          onClick={onExit}
          className="mt-4 px-7 py-3 rounded-full font-black text-white shadow-lg"
          style={{ background: '#FF9600', boxShadow: '0 4px 0 #cc7a00' }}
        >
          全機能を開く →
        </button>
      )}

      {/* ── すべての機能を見る ────────────────────────────────── */}
      <button
        onClick={onExit}
        className="mt-4 mb-10 text-xs font-semibold underline text-duo-gray"
      >
        すべての機能を見る
      </button>
    </div>
  );
};
