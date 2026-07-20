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

const MAX_DAYS = 5;
const NS90_KEY = 'ns90.activeDates';
const IOS_APP_STORE = 'https://apps.apple.com/jp/app/fitingo/id6742592440';

const openIOS = (mode: string) => {
  window.location.href = `kfit://mode/${mode}`;
  setTimeout(() => { window.location.href = IOS_APP_STORE; }, 2000);
};

const AppleLogo: React.FC<{ size?: number }> = ({ size = 16 }) => (
  <svg viewBox="0 0 814 1000" style={{ width: size, height: size, fill: 'currentColor', flexShrink: 0 }}>
    <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.3-60.8-155.5-127.4C46 790.7 0 663 0 541.8c0-207.5 133.4-317.1 264.11-317.1 70.2 0 128.9 46.5 168.6 46.5 36.5 0 107.1-49 192.5-49 30.8 0 112.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/>
  </svg>
);
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
  /** 見出し「今度こそ、続く」の下に表示するモード名（かっこ書き） */
  modeName: string;
  /** バッジ（ボタン）の直後に続くメッセージ。例: [FIT 90秒]＋「を押して始める、それだけ」 */
  actionSuffix: string;
  accent: string;
  accentDark: string;
  accentLight: string;
  bg: string;
  emoji: string | null; // null = GIF
  /** iOS アプリボタンのラベル */
  iosLabel: string;
}

const MODES: ModeConfig[] = [
  {
    id: 'fit',
    badge: 'FIT 90秒',
    modeName: '筋トレ',
    actionSuffix: 'で始める、それだけ',
    accent: '#58CC02',
    accentDark: '#46A302',
    accentLight: 'rgba(88,204,2,0.1)',
    bg: 'linear-gradient(180deg,#F0FFF4 0%,#fff 100%)',
    emoji: null,
    iosLabel: 'iOSアプリで筋トレ',
  },
  {
    id: 'diet',
    badge: 'DIET',
    modeName: 'ダイエット',
    actionSuffix: 'ボタンで計測、それだけ',
    accent: '#CE82FF',
    accentDark: '#9C5CC9',
    accentLight: 'rgba(206,130,255,0.1)',
    bg: 'linear-gradient(180deg,#F8F0FF 0%,#fff 100%)',
    emoji: '⚖️',
    iosLabel: 'iOSアプリでダイエット',
  },
  {
    id: 'food',
    badge: 'FOOD',
    modeName: '食事ログ',
    actionSuffix: 'ボタンで撮る、それだけ',
    accent: '#FF9600',
    accentDark: '#CC7700',
    accentLight: 'rgba(255,150,0,0.1)',
    bg: 'linear-gradient(180deg,#FFF8F0 0%,#fff 100%)',
    emoji: '📷',
    iosLabel: 'iOSアプリで食事ログ',
  },
  {
    id: 'edu',
    badge: 'EDU',
    modeName: '語学',
    actionSuffix: 'ボタンで例文、それだけ',
    accent: '#1CB0F6',
    accentDark: '#1090CC',
    accentLight: 'rgba(28,176,246,0.1)',
    bg: 'linear-gradient(180deg,#F0F8FF 0%,#fff 100%)',
    emoji: '📚',
    iosLabel: 'iOSアプリで語学',
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
  /** 最初に表示するモード（LandingPage から渡す） */
  initialMode?: string;
}

// ─── メインコンポーネント ───────────────────────────────────────────────────────

export const NinetySecondMode: React.FC<Props> = ({
  onStart, onFoodLog, onEduLog, onDietLog, onExit, doneToday = false, initialMode,
}) => {
  const [activePage, setActivePage] = useState(() => {
    if (initialMode) {
      const idx = MODES.findIndex((m) => m.id === initialMode);
      return idx >= 0 ? idx : 0;
    }
    return 0;
  });
  const [gifIdx, setGifIdx] = useState(0);
  const [tipIdx, setTipIdx] = useState(0);
  const [activeDays, setActiveDays] = useState<string[]>(getActiveDays);
  const [pulse, setPulse] = useState(false);

  const scrollRef = useRef<HTMLDivElement>(null);
  const graduated = activeDays.length >= MAX_DAYS;
  const mode = MODES[activePage];

  // ── 初期モードへのスクロール ────────────────────────────────────────────────
  useEffect(() => {
    if (activePage === 0) return;
    // マウント後に初期ページへスクロール（scroll-snap が機能するため即時）
    requestAnimationFrame(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollLeft = activePage * scrollRef.current.clientWidth;
      }
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
      <div style={{ display: 'flex', justifyContent: 'center', gap: 8, paddingTop: 16, paddingBottom: 4 }}>
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
            onAction={handleAction}
            onExit={onExit}
          />
        ))}
      </div>

      {/* ── 全機能ボタン（ポチポチと重ならないよう独立セクションに）──── */}
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          paddingBottom: 40,
          paddingTop: 16,
          gap: 10,
          background: 'transparent',
        }}
      >
        {/* ── 5日達成 SNS 共有カード ───────────────────────────────── */}
        {graduated && (
          <div
            style={{
              width: 'calc(100vw - 48px)',
              maxWidth: 380,
              borderRadius: 22,
              border: '2px solid #58CC02',
              background: 'linear-gradient(135deg, #F0FFF4 0%, #DCFCE7 100%)',
              padding: '22px 22px 18px',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 10,
              textAlign: 'center',
            }}
          >
            <div style={{ fontSize: 44 }}>🎉</div>
            <div style={{ fontSize: 24, fontWeight: 900, color: '#1f1f1f', lineHeight: 1.2 }}>
              5日、続きました。
            </div>
            <div style={{ fontSize: 16, fontWeight: 700, color: '#46A302' }}>
              今度こそ、続く。
            </div>
            <div style={{ display: 'flex', gap: 10, fontSize: 26, margin: '2px 0' }}>
              {['💪', '⚖️', '🍱', '📚'].map((e) => <span key={e}>{e}</span>)}
            </div>
            <div style={{ fontSize: 12, color: '#777', fontWeight: 500 }}>
              仲間に広めて、一緒に始めよう
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 4, flexWrap: 'wrap', justifyContent: 'center' }}>
              <a
                href={`https://twitter.com/intent/tweet?text=${encodeURIComponent('5日続けました！\n今度こそ、続く。\n#Fitingo #今度こそ続く')}&url=${encodeURIComponent('https://kfitapp.web.app')}`}
                target="_blank"
                rel="noreferrer"
                style={{
                  padding: '10px 20px',
                  borderRadius: 999,
                  background: '#000',
                  color: '#fff',
                  fontWeight: 900,
                  fontSize: 13,
                  textDecoration: 'none',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 6,
                }}
              >
                𝕏 でシェア
              </a>
              <a
                href={`https://line.me/R/msg/text/?${encodeURIComponent('5日続けました！\n今度こそ、続く。\n#Fitingo\nhttps://kfitapp.web.app')}`}
                target="_blank"
                rel="noreferrer"
                style={{
                  padding: '10px 20px',
                  borderRadius: 999,
                  background: '#06C755',
                  color: '#fff',
                  fontWeight: 900,
                  fontSize: 13,
                  textDecoration: 'none',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 6,
                }}
              >
                LINE でシェア
              </a>
            </div>
          </div>
        )}

        {graduated && (
          <button
            onClick={onExit}
            style={{
              padding: '12px 28px',
              borderRadius: 999,
              fontWeight: 900,
              fontSize: 15,
              color: '#fff',
              background: '#FF9600',
              boxShadow: '0 4px 0 #cc7a00',
              border: 'none',
              cursor: 'pointer',
            }}
          >
            全機能を開く →
          </button>
        )}
        {/* 卒業後は「全機能を開く」ボタンがあるためリンクは非表示（表示の重複を避ける） */}
        {!graduated && (
          <button
            onClick={onExit}
            style={{
              fontSize: 12,
              fontWeight: 600,
              color: '#afafaf',
              textDecoration: 'underline',
              background: 'transparent',
              border: 'none',
              cursor: 'pointer',
              padding: '4px 8px',
            }}
          >
            すべての機能を見る
          </button>
        )}
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
  onAction: () => void;
  onExit: () => void;
}

const ModeCard: React.FC<CardProps> = ({
  mode, gifIdx, tipIdx, tipList, activeDays, graduated, doneToday,
  pulse, onAction,
}) => {
  const { accent, accentDark } = mode;
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

      {/* ── Fitingo アイコン（最上部に小さく表示）───────────────────── */}
      <img
        src="/mascot.png"
        alt="Fitingo"
        className="mt-4"
        style={{ width: 56, height: 56, objectFit: 'contain', borderRadius: '50%' }}
      />

      {/* ── 連続日数（あと◯日で全開放）＋ 5日チェックマーク ─────────────── */}
      <div className="mt-3 flex flex-col items-center" style={{ gap: 10 }}>
        <p style={{ margin: 0, textAlign: 'center' }}>
          <span style={{ fontSize: 20, fontWeight: 900, color: '#1f1f1f' }}>
            🔥{streak}日連続
          </span>
          <span style={{ fontSize: 14, fontWeight: 700, color: graduated ? '#FF9600' : '#777' }}>
            {graduated ? '　🎉全機能開放中！' : `（あと${MAX_DAYS - streak}日で全開放）`}
          </span>
        </p>
        <div className="flex" style={{ gap: 12 }}>
          {Array.from({ length: MAX_DAYS }).map((_, i) => (
            <div
              key={i}
              style={{
                width: 20, height: 20, borderRadius: '50%',
                background: i < activeDays.length ? accent : '#e5e5e5',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: i < activeDays.length ? `0 2px 6px ${accent}66` : 'none',
              }}
            >
              {i < activeDays.length && (
                <span style={{ color: '#fff', fontSize: 11, fontWeight: 900, lineHeight: 1 }}>✓</span>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* ── 大見出し：今度こそ、続く／「モード名」──────────────────────── */}
      <div className="mt-5 flex flex-col items-center px-4" style={{ gap: 2 }}>
        <p
          className="text-4xl font-black tracking-tight text-center"
          style={{ color: accent, textShadow: `0 2px 8px ${accent}33`, margin: 0 }}
        >
          今度こそ、続く
        </p>
        <p
          className="text-4xl font-black tracking-tight text-center"
          style={{ color: accent, textShadow: `0 2px 8px ${accent}33`, margin: 0 }}
        >
          「{mode.modeName}」
        </p>
      </div>

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
        // EDU: 語学記録ボタン（常に表示）
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
      ) : (
        // FIT: お手本動画をそのままボタンに / DIET: Fitingo 画像ボタン（丸バックなし）
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
          {mode.id === 'fit' ? (
            <img
              key={gifIdx}
              src={GIFS[gifIdx % GIFS.length]}
              alt="お手本動画"
              style={{ width: 190, height: 190, objectFit: 'cover', borderRadius: 24 }}
            />
          ) : (
            <img
              src="/mascot.png"
              alt="Fitingo"
              style={{ width: 190, height: 190, objectFit: 'contain', borderRadius: '50%' }}
            />
          )}
        </button>
      )}

      {/* ── モードバッジ（ボタン）+ メッセージ ─────────────────────────── */}
      {/* 例: [FIT 90秒] で始める、それだけ（バッジ自体がアクショントリガー）*/}
      {doneToday ? (
        <p className="mt-4 font-black" style={{ color: '#1f1f1f', fontSize: 18 }}>
          ✅ 今日は完了！
        </p>
      ) : (
        <div
          className="mt-4 flex items-center flex-wrap justify-center"
          style={{ gap: 8, padding: '0 16px' }}
        >
          <button
            onClick={onAction}
            style={{
              background: accent,
              border: 'none',
              cursor: 'pointer',
              borderRadius: 999,
              color: '#fff',
              fontWeight: 900,
              fontSize: 16,
              padding: '7px 20px',
              boxShadow: `0 3px 10px ${accent}55`,
            }}
          >
            {mode.badge}
          </button>
          <span style={{ color: '#333', fontWeight: 900, fontSize: 22 }}>
            {mode.actionSuffix}
          </span>
        </div>
      )}

      {/* ── Tips（実施後はシンプルにするため非表示）──────────────────── */}
      {!doneToday && (
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
      )}

      {/* ── iOS アプリ誘導ボタン（コンパクト）──────────────────────────── */}
      <button
        onClick={() => openIOS(mode.id)}
        style={{
          marginTop: 14,
          padding: '8px 16px',
          borderRadius: 999,
          background: accent,
          border: 'none',
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 6,
          boxShadow: `0 2px 0 ${accentDark}`,
          color: '#fff',
          transition: 'opacity 0.15s',
        }}
        onMouseEnter={(e) => (e.currentTarget.style.opacity = '0.85')}
        onMouseLeave={(e) => (e.currentTarget.style.opacity = '1')}
      >
        <AppleLogo size={13} />
        <span style={{ fontWeight: 800, fontSize: 12, letterSpacing: '-0.1px' }}>
          {mode.iosLabel}
        </span>
      </button>
    </div>
  );
};
