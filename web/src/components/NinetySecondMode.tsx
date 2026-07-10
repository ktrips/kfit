import React, {
  useEffect, useRef, useState, useCallback,
} from 'react';

// ─── 定数 ──────────────────────────────────────────────────────────────────

const GIFS = [
  '/fitingo_wo_pushups.gif',
  '/fitingo_workout.gif',
  '/fitingo_wo_squat.gif',
];

const TIPS: Record<string, string[]> = {
  fit:  ['💡 たった5回から始めよう！', '⚡ 90秒で体が変わる！', '🔥 毎日続けると体が軽くなる！', '💪 小さな積み重ねが大きな変化！'],
  food: ['📸 撮るだけで栄養計算！', '🥗 食事の見える化が続く秘訣', '🍱 まず1枚、今日から始めよう', '✨ 記録するだけで意識が変わる！'],
  edu:  ['📖 1レッスン5分でOK！', '🌏 毎日続けると会話力がつく', '🗣️ スクショ1枚が語学の習慣に', '⭐ 継続こそが最強の勉強法！'],
  diet: ['⚖️ 毎朝の計測が成功の鍵', '📉 記録するだけで体重が落ちる', '🎯 数値を見ると行動が変わる', '🌟 小さな変化を見逃さないで！'],
};

const MAX_DAYS = 7;
const NS90_KEY = 'ns90.activeDates';
const NS90_TOP = 'ns90.topVisible';

const todayStr = () => new Date().toISOString().slice(0, 10);

function getActiveDays(): string[] {
  try { return JSON.parse(localStorage.getItem(NS90_KEY) ?? '[]'); }
  catch { return []; }
}
function recordToday(): string[] {
  const today = todayStr();
  const days = getActiveDays();
  if (days.includes(today)) return days;
  const next = [...days, today].slice(-MAX_DAYS);
  localStorage.setItem(NS90_KEY, JSON.stringify(next));
  return next;
}

// ─── モード定義 ──────────────────────────────────────────────────────────────

interface ModeConfig {
  id: string;
  badge: string;
  tagline: string;
  /** バッジ（ボタン）の直後に続くメッセージ。例: [FIT 90秒]＋「を押して始める、それだけ」 */
  actionSuffix: string;
  accent: string;
  accentDark: string;
  accentLight: string;
  bg: string;
  emoji: string | null; // null = GIF
}

const MODES: ModeConfig[] = [
  {
    id: 'fit',
    badge: 'FIT 90秒',
    tagline: '今度こそ、続く「筋トレ」',
    actionSuffix: 'を押して始める、それだけ',
    accent: '#58CC02',
    accentDark: '#46A302',
    accentLight: 'rgba(88,204,2,0.1)',
    bg: 'linear-gradient(180deg,#F0FFF4 0%,#fff 100%)',
    emoji: null,
  },
  {
    id: 'diet',
    badge: 'DIET 90秒',
    tagline: '今度こそ、続く「ダイエット」',
    actionSuffix: 'を押して計測する、それだけ',
    accent: '#CE82FF',
    accentDark: '#9C5CC9',
    accentLight: 'rgba(206,130,255,0.1)',
    bg: 'linear-gradient(180deg,#F8F0FF 0%,#fff 100%)',
    emoji: '⚖️',
  },
  {
    id: 'food',
    badge: 'FOOD 90秒',
    tagline: '今度こそ、続く「食事ログ」',
    actionSuffix: 'を押して撮る、それだけ',
    accent: '#FF9600',
    accentDark: '#CC7700',
    accentLight: 'rgba(255,150,0,0.1)',
    bg: 'linear-gradient(180deg,#FFF8F0 0%,#fff 100%)',
    emoji: '📷',
  },
  {
    id: 'edu',
    badge: 'EDU 90秒',
    tagline: '今度こそ、続く「語学」',
    actionSuffix: 'を押して記録する、それだけ',
    accent: '#1CB0F6',
    accentDark: '#1090CC',
    accentLight: 'rgba(28,176,246,0.1)',
    bg: 'linear-gradient(180deg,#F0F8FF 0%,#fff 100%)',
    emoji: '📚',
  },
];

// ─── Props ────────────────────────────────────────────────────────────────────

interface Props {
  onStart:      () => void;  // FIT: ワークアウト
  onFoodLog?:   () => void;  // FOOD: 食事ログ
  onEduLog?:    () => void;  // EDU: 語学ログ
  onDietLog?:   () => void;  // DIET: 体重記録
  onExit:       () => void;
  doneToday?:   boolean;
}

// ─── メインコンポーネント ───────────────────────────────────────────────────────

export const NinetySecondMode: React.FC<Props> = ({
  onStart, onFoodLog, onEduLog, onDietLog, onExit, doneToday = false,
}) => {
  const [activePage, setActivePage] = useState(0);
  const [gifIdx, setGifIdx] = useState(0);
  const [tipIdx, setTipIdx] = useState(0);
  const [activeDays, setActiveDays] = useState<string[]>(getActiveDays);
  const [pulse, setPulse] = useState(false);
  const [topVisible, setTopVisible] = useState(() => {
    try { return localStorage.getItem(NS90_TOP) !== 'false'; } catch { return true; }
  });

  const scrollRef = useRef<HTMLDivElement>(null);
  const graduated = activeDays.length >= MAX_DAYS;
  const mode = MODES[activePage];

  // ── スクロール → ページ同期 ─────────────────────────────────────────────────
  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const page = Math.round(el.scrollLeft / el.clientWidth);
    setActivePage(page);
  }, []);

  const goToPage = (idx: number) => {
    scrollRef.current?.scrollTo({ left: idx * (scrollRef.current.clientWidth), behavior: 'smooth' });
  };

  // ── GIF ローテーション（10秒）─────────────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setGifIdx((i) => (i + 1) % GIFS.length), 10_000);
    return () => clearInterval(t);
  }, []);

  // ── Tips ローテーション（4秒）─────────────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setTipIdx((i) => (i + 1) % (TIPS[mode.id]?.length ?? 4)), 4_000);
    return () => clearInterval(t);
  }, [mode.id]);

  // ── ボタンパルス ─────────────────────────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setPulse((p) => !p), 1600);
    return () => clearInterval(t);
  }, []);

  // ── トップウィンドウ 永続化 ──────────────────────────────────────────────
  const toggleTop = (v: boolean) => {
    setTopVisible(v);
    try { localStorage.setItem(NS90_TOP, String(v)); } catch {}
  };

  // ── アクション ────────────────────────────────────────────────────────────
  const handleAction = () => {
    const updated = recordToday();
    setActiveDays(updated);
    switch (mode.id) {
      case 'fit':  onStart(); break;
      case 'food': onFoodLog ? onFoodLog() : onExit(); break;
      case 'edu':  onEduLog  ? onEduLog()  : onExit(); break;
      case 'diet': onDietLog ? onDietLog() : onExit(); break;
    }
  };

  return (
    <div className="min-h-screen overflow-hidden" style={{ background: mode.bg }}>

      {/* ── ページインジケータ（モード切替ドット）─────────────────────── */}
      <div className="flex justify-center gap-2 pt-5 pb-1">
        {MODES.map((m, i) => (
          <button
            key={m.id}
            onClick={() => goToPage(i)}
            style={{
              width: i === activePage ? 28 : 8,
              height: 8,
              borderRadius: 4,
              background: i === activePage ? mode.accent : '#e5e5e5',
              transition: 'all 0.3s ease',
              border: 'none',
              cursor: 'pointer',
              padding: 0,
            }}
          />
        ))}
      </div>

      {/* ── 水平スクロール カルーセル ──────────────────────────────────── */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        style={{
          display: 'flex',
          overflowX: 'scroll',
          scrollSnapType: 'x mandatory',
          scrollbarWidth: 'none',
          WebkitOverflowScrolling: 'touch',
        }}
        className="w-full"
      >
        {MODES.map((m, idx) => (
          <ModeCard
            key={m.id}
            mode={m}
            isActive={idx === activePage}
            gifIdx={gifIdx}
            tipIdx={tipIdx}
            tipList={TIPS[m.id] ?? TIPS.fit}
            activeDays={activeDays}
            graduated={graduated}
            doneToday={doneToday}
            pulse={pulse}
            topVisible={topVisible}
            onToggleTop={toggleTop}
            onAction={handleAction}
            onExit={onExit}
          />
        ))}
      </div>

      {/* ── 全機能ボタン ─────────────────────────────────────────────── */}
      <div className="flex flex-col items-center pb-10 gap-2" style={{ marginTop: -8 }}>
        {graduated && (
          <button
            onClick={onExit}
            className="px-7 py-3 rounded-full font-black text-white shadow-lg"
            style={{ background: '#FF9600', boxShadow: '0 4px 0 #cc7a00' }}
          >
            全機能を開く →
          </button>
        )}
        <button
          onClick={onExit}
          className="text-xs font-semibold underline"
          style={{ color: '#afafaf' }}
        >
          すべての機能を見る
        </button>
      </div>
    </div>
  );
};

// ─── モードカード ─────────────────────────────────────────────────────────────

interface CardProps {
  mode: ModeConfig;
  isActive: boolean;
  gifIdx: number;
  tipIdx: number;
  tipList: string[];
  activeDays: string[];
  graduated: boolean;
  doneToday: boolean;
  pulse: boolean;
  topVisible: boolean;
  onToggleTop: (v: boolean) => void;
  onAction: () => void;
  onExit: () => void;
}

const ModeCard: React.FC<CardProps> = ({
  mode, gifIdx, tipIdx, tipList, activeDays, graduated, doneToday,
  pulse, topVisible, onToggleTop, onAction,
}) => {
  const { accent, accentDark, accentLight } = mode;
  const streak = activeDays.length;

  return (
    <div
      style={{
        minWidth: '100vw',
        scrollSnapAlign: 'center',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        paddingBottom: 16,
      }}
    >
      {/* ── ストリーク ────────────────────────────────────────────────── */}
      <div className="flex items-center gap-1.5 mt-3">
        <span className="text-xl">🔥</span>
        <span className="text-base font-black" style={{ color: '#1f1f1f' }}>
          {streak}日連続
        </span>
      </div>

      {/* ── コンテンツ窓（表示 / 非表示）────────────────────────────── */}
      {topVisible ? (
        <div
          className="relative mx-6 mt-4 overflow-hidden rounded-2xl shadow-md"
          style={{ width: 'calc(100vw - 48px)', maxWidth: 400, height: 156 }}
        >
          {/* コンテンツ本体（窓全体がアクショントリガー）*/}
          {mode.emoji === null ? (
            // FIT: GIF（クリックで開始）
            <button
              onClick={onAction}
              style={{
                width: '100%', height: '100%',
                border: 'none', padding: 0, cursor: 'pointer',
                background: 'transparent', display: 'block',
              }}
              aria-label="タップして始める"
            >
              <img
                key={gifIdx}
                src={GIFS[gifIdx % GIFS.length]}
                alt="exercise"
                style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
              />
            </button>
          ) : (
            // FOOD / EDU / DIET: 絵文字ボタン
            <button
              onClick={onAction}
              style={{
                width: '100%', height: '100%',
                background: accentLight,
                border: 'none', cursor: 'pointer',
                display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center', gap: 6,
              }}
              aria-label="タップして始める"
            >
              <span style={{ fontSize: 64 }}>{mode.emoji}</span>
              {mode.id === 'edu' && (
                <span className="text-sm font-black" style={{ color: accent }}>
                  タップして語学を記録
                </span>
              )}
            </button>
          )}

          {/* 隠すボタン（右上）*/}
          <button
            onClick={() => onToggleTop(false)}
            style={{
              position: 'absolute', top: 8, right: 8,
              background: 'rgba(255,255,255,0.85)',
              border: 'none', borderRadius: '50%',
              width: 28, height: 28,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: 'pointer', boxShadow: '0 1px 4px rgba(0,0,0,0.15)',
            }}
            aria-label="動画を隠す"
          >
            <span style={{ fontSize: 13, color: accent, fontWeight: 900 }}>✕</span>
          </button>
        </div>
      ) : (
        // 表示ボタン（コンパクト）
        <button
          onClick={() => onToggleTop(true)}
          className="mt-4 flex items-center gap-1.5 px-4 py-2 rounded-full font-semibold text-sm"
          style={{ background: accentLight, color: accent, border: 'none', cursor: 'pointer' }}
        >
          <span>▼</span>
          <span>動画を表示</span>
        </button>
      )}

      {/* ── タグライン ──────────────────────────────────────────────── */}
      <p
        className="mt-5 text-3xl font-black tracking-tight text-center px-4"
        style={{ color: accent, textShadow: `0 2px 8px ${accent}33` }}
      >
        {mode.tagline}
      </p>

      {/* ── メインボタン（モード別）──────────────────────────────────── */}
      {mode.id === 'food' ? (
        // FOOD: 大型 AI 食事フォトログ ボタン
        <button
          onClick={onAction}
          style={{
            marginTop: 20,
            width: 'calc(100vw - 48px)',
            maxWidth: 380,
            padding: '20px 24px',
            borderRadius: 20,
            background: accent,
            boxShadow: `0 6px 0 ${accentDark}, 0 0 ${pulse ? 24 : 12}px ${accent}55`,
            border: 'none',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: 16,
            transform: `scale(${pulse ? 1.02 : 1.0})`,
            transition: 'transform 1.6s ease-in-out, box-shadow 1.6s ease-in-out',
          }}
        >
          <span style={{ fontSize: 36 }}>📸</span>
          <div style={{ textAlign: 'left', flex: 1 }}>
            <div style={{ color: '#fff', fontWeight: 900, fontSize: 20 }}>
              AI食事フォトログ
            </div>
            <div style={{ color: 'rgba(255,255,255,0.85)', fontWeight: 600, fontSize: 12 }}>
              写真を撮るだけでカロリー自動記録
            </div>
          </div>
          <span style={{ color: '#fff', fontSize: 18, fontWeight: 900 }}>›</span>
        </button>
      ) : mode.id === 'edu' ? (
        // EDU: コンテンツ窓が非表示の場合のみボタン（表示時は窓がボタン）
        !topVisible ? (
          <button
            onClick={onAction}
            style={{
              marginTop: 20,
              width: 'calc(100vw - 48px)',
              maxWidth: 380,
              padding: '20px 24px',
              borderRadius: 20,
              background: accent,
              boxShadow: `0 6px 0 ${accentDark}`,
              border: 'none',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 12,
            }}
          >
            <span style={{ fontSize: 32 }}>📚</span>
            <span style={{ color: '#fff', fontWeight: 900, fontSize: 20 }}>語学を記録</span>
          </button>
        ) : null
      ) : (
        // FIT / DIET: Fitingo 画像ボタン（丸バックなし）
        <button
          onClick={onAction}
          style={{
            marginTop: 20,
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
            padding: 0,
            transform: `scale(${pulse ? 1.04 : 1.0})`,
            transition: 'transform 1.6s ease-in-out',
            filter: `drop-shadow(0 8px 16px ${accent}55)`,
          }}
          aria-label={doneToday ? 'もう1セット' : `${mode.badge}${mode.actionSuffix}`}
        >
          <img
            src="/mascot.png"
            alt="Fitingo"
            style={{ width: 190, height: 190, objectFit: 'contain', borderRadius: '50%' }}
          />
        </button>
      )}

      {/* ── モードバッジ（ボタン）+ メッセージ ─────────────────────────── */}
      {/* 例: [FIT 90秒] を押して始める、それだけ（バッジ自体がアクショントリガー）*/}
      {doneToday ? (
        <p className="mt-4 text-sm font-semibold" style={{ color: '#999' }}>
          もう1セットやる ▶
        </p>
      ) : (
        <div className="mt-4 flex items-center gap-1.5 flex-wrap justify-center px-4">
          <button
            onClick={onAction}
            className="text-xs font-black px-4 py-1.5 rounded-full text-white"
            style={{
              background: accent,
              border: 'none',
              cursor: 'pointer',
              boxShadow: `0 2px 8px ${accent}55`,
            }}
          >
            {mode.badge}
          </button>
          <span className="text-sm font-bold" style={{ color: '#666' }}>
            {mode.actionSuffix}
          </span>
        </div>
      )}

      {/* ── Tips ─────────────────────────────────────────────────────── */}
      <div className="mt-4 flex items-center gap-2 px-6" style={{ maxWidth: 380 }}>
        <img
          src="/mascot.png"
          alt="Fitingo"
          style={{ width: 24, height: 24, borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }}
        />
        <p className="text-sm font-semibold" style={{ color: '#999' }}>
          {tipList[tipIdx % tipList.length]}
        </p>
      </div>

      {/* ── 7日進捗ドット ──────────────────────────────────────────────── */}
      <div className="mt-5 flex flex-col items-center gap-2">
        <div className="flex gap-2.5">
          {Array.from({ length: MAX_DAYS }).map((_, i) => (
            <div
              key={i}
              style={{
                width: 14, height: 14, borderRadius: '50%',
                background: i < activeDays.length ? accent : '#e5e5e5',
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
    </div>
  );
};
