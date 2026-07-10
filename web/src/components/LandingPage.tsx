import React, { useState } from 'react';
import { signInWithGoogle } from '../services/firebase';
import { useAppStore } from '../store/appStore';

// ─── 定数 ────────────────────────────────────────────────────────────────────
export type Mode90 = 'fit' | 'diet' | 'food' | 'edu';
export const NS90_MODE_KEY = 'ns90.selectedMode';
const NS90_DATES_KEY = 'ns90.activeDates';

export function getActiveDays(): string[] {
  try { return JSON.parse(localStorage.getItem(NS90_DATES_KEY) ?? '[]'); }
  catch { return []; }
}

const MODES: {
  id: Mode90; emoji: string; label: string; sublabel: string;
  accent: string; accentDark: string; bg: string;
}[] = [
  {
    id: 'fit',
    emoji: '💪',
    label: '筋トレ',
    sublabel: '90秒で体を動かそう',
    accent: '#58CC02',
    accentDark: '#46A302',
    bg: 'rgba(88,204,2,0.08)',
  },
  {
    id: 'diet',
    emoji: '⚖️',
    label: 'ダイエット',
    sublabel: '毎日1回の体重記録から',
    accent: '#CE82FF',
    accentDark: '#9C5CC9',
    bg: 'rgba(206,130,255,0.08)',
  },
  {
    id: 'food',
    emoji: '🍱',
    label: '食事ログ',
    sublabel: '写真1枚でカロリー管理',
    accent: '#FF9600',
    accentDark: '#CC7700',
    bg: 'rgba(255,150,0,0.08)',
  },
  {
    id: 'edu',
    emoji: '📚',
    label: '語学',
    sublabel: 'スクショ1枚でAI例文作成',
    accent: '#1CB0F6',
    accentDark: '#1090CC',
    bg: 'rgba(28,176,246,0.08)',
  },
];

const IOS_APP_STORE = 'https://apps.apple.com/jp/app/fitingo/id6742592440';
const IOS_SCHEME_BASE = 'kfit://mode/';

interface Props {
  onAuthenticated: (mode: Mode90) => void;
}

export const LandingPage: React.FC<Props> = ({ onAuthenticated }) => {
  const setUser = useAppStore((s) => s.setUser);
  const setError = useAppStore((s) => s.setError);
  const [loadingMode, setLoadingMode] = useState<Mode90 | null>(null);

  // Googleログイン + モード指定
  const handleSelectMode = async (mode: Mode90) => {
    localStorage.setItem(NS90_MODE_KEY, mode);
    setLoadingMode(mode);
    try {
      const user = await signInWithGoogle();
      setUser(user);
      onAuthenticated(mode);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'ログインに失敗しました');
    } finally {
      setLoadingMode(null);
    }
  };

  // iOSアプリの起動を試みる（未インストール時は App Store へ）
  const openIOS = (mode: Mode90) => {
    const deepLink = `${IOS_SCHEME_BASE}${mode}`;
    const start = Date.now();
    const win = window.open(deepLink, '_blank');
    setTimeout(() => {
      if (!win || win.closed || Date.now() - start < 2000) {
        window.open(IOS_APP_STORE, '_blank');
      }
    }, 1500);
  };

  return (
    <div
      className="min-h-screen flex flex-col items-center"
      style={{ background: 'linear-gradient(160deg,#F0FFF4 0%,#EFF6FF 50%,#FFF8F0 100%)' }}
    >
      {/* ── ロゴ ───────────────────────────────────────────────── */}
      <div className="flex flex-col items-center pt-14 pb-6">
        <div className="relative mb-4">
          <img
            src="/mascot.png"
            alt="Fitingo"
            className="w-24 h-24 rounded-full object-cover"
            style={{ border: '4px solid #58CC02', boxShadow: '0 6px 0 #46A302' }}
          />
        </div>
        <span className="text-2xl font-black text-duo-green tracking-tight mb-1">Fitingo</span>
      </div>

      {/* ── ヒーローテキスト ────────────────────────────────────── */}
      <h1
        className="text-5xl font-black text-center leading-tight tracking-tight mb-2"
        style={{ color: '#1f1f1f' }}
      >
        今度こそ、<br />続く。
      </h1>
      <p className="text-base font-semibold text-center mb-10" style={{ color: '#777' }}>
        何を続ける？ 7日間だけ試してみよう。
      </p>

      {/* ── 4モードボタン ──────────────────────────────────────── */}
      <div className="flex flex-col gap-4 w-full px-6" style={{ maxWidth: 420 }}>
        {MODES.map((m) => {
          const isLoading = loadingMode === m.id;
          return (
            <div key={m.id}>
              {/* メインボタン（Googleログイン） */}
              <button
                onClick={() => handleSelectMode(m.id)}
                disabled={loadingMode !== null}
                style={{
                  width: '100%',
                  padding: '18px 20px',
                  borderRadius: 20,
                  background: isLoading ? m.accentDark : m.bg,
                  border: `2.5px solid ${m.accent}`,
                  cursor: loadingMode ? 'default' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 16,
                  opacity: loadingMode !== null && !isLoading ? 0.55 : 1,
                  transition: 'all 0.2s ease',
                  boxShadow: isLoading ? `0 4px 0 ${m.accentDark}` : `0 3px 0 ${m.accent}44`,
                }}
              >
                <span style={{ fontSize: 36 }}>{m.emoji}</span>
                <div style={{ textAlign: 'left', flex: 1 }}>
                  <div style={{ fontSize: 20, fontWeight: 900, color: isLoading ? '#fff' : '#1f1f1f' }}>
                    {m.label}
                  </div>
                  <div style={{ fontSize: 12, fontWeight: 600, color: isLoading ? 'rgba(255,255,255,0.85)' : '#888', marginTop: 2 }}>
                    {isLoading ? 'Googleでログイン中…' : m.sublabel}
                  </div>
                </div>
                {isLoading ? (
                  <div
                    style={{
                      width: 20, height: 20, borderRadius: '50%',
                      border: '2.5px solid rgba(255,255,255,0.4)',
                      borderTopColor: '#fff',
                      animation: 'spin 0.7s linear infinite',
                    }}
                  />
                ) : (
                  <span style={{ fontSize: 18, color: m.accent, fontWeight: 900 }}>›</span>
                )}
              </button>

              {/* iOS アプリで開くリンク */}
              <button
                onClick={() => openIOS(m.id)}
                style={{
                  marginTop: 6,
                  marginLeft: 8,
                  background: 'transparent',
                  border: 'none',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 5,
                  padding: '2px 0',
                }}
              >
                <span style={{ fontSize: 13 }}>📱</span>
                <span style={{ fontSize: 11, color: m.accent, fontWeight: 700, textDecoration: 'underline' }}>
                  iOSアプリで{m.label}を始める
                </span>
              </button>
            </div>
          );
        })}
      </div>

      {/* ── フッター説明 ────────────────────────────────────────── */}
      <div className="mt-10 mb-6 text-center px-8">
        <p className="text-xs font-semibold" style={{ color: '#aaa', lineHeight: 1.8 }}>
          Googleアカウントでログイン後、<br />
          選んだカテゴリの90秒モードがスタート。<br />
          <span style={{ color: '#58CC02', fontWeight: 900 }}>7日間続けると全機能が解放！</span>
        </p>
      </div>

      {/* ── スピン アニメーション ────────────────────────────────── */}
      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
};
