import React, { useState, useEffect, useRef } from 'react';
import { signInWithGoogle, subscribeLiveCount, incrementLiveCount } from '../services/firebase';
import { useAppStore } from '../store/appStore';
import { detectInAppBrowser, openInExternalBrowser, IN_APP_BROWSER_LABEL } from '../utils/inAppBrowser';

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
  accent: string; accentDark: string;
}[] = [
  { id: 'fit',  emoji: '💪', label: '筋トレ',    sublabel: '90秒で体を動かそう',      accent: '#58CC02', accentDark: '#46A302' },
  { id: 'diet', emoji: '⚖️', label: 'ダイエット', sublabel: '毎日1回の体重記録から',    accent: '#CE82FF', accentDark: '#9C5CC9' },
  { id: 'food', emoji: '🍱', label: '食事ログ',   sublabel: '写真1枚でカロリー管理',   accent: '#FF9600', accentDark: '#CC7700' },
  { id: 'edu',  emoji: '📚', label: '語学',       sublabel: 'スクショ1枚でAI例文作成', accent: '#1CB0F6', accentDark: '#1090CC' },
];

const IOS_APP_STORE = 'https://apps.apple.com/jp/app/fitingo/id6742592440';

// カスタムURLスキーム → 未インストール時は App Store へ
const openIOS = (mode: Mode90) => {
  window.location.href = `kfit://mode/${mode}`;
  setTimeout(() => { window.location.href = IOS_APP_STORE; }, 2000);
};

// Apple ロゴ SVG（白抜き）
const AppleLogo = ({ size = 16 }: { size?: number }) => (
  <svg viewBox="0 0 814 1000" style={{ width: size, height: size, fill: 'currentColor', flexShrink: 0 }}>
    <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.3-60.8-155.5-127.4C46 790.7 0 663 0 541.8c0-207.5 133.4-317.1 264.11-317.1 70.2 0 128.9 46.5 168.6 46.5 36.5 0 107.1-49 192.5-49 30.8 0 112.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/>
  </svg>
);

interface Props {
  onAuthenticated: (mode: Mode90) => void;
}

export const LandingPage: React.FC<Props> = ({ onAuthenticated }) => {
  const setUser = useAppStore((s) => s.setUser);
  const setError = useAppStore((s) => s.setError);
  const [loadingMode, setLoadingMode] = useState<Mode90 | null>(null);
  const [liveCount, setLiveCount] = useState<number>(0);
  const incrementedRef = useRef(false);
  const inAppBrowser = detectInAppBrowser();

  // ライブカウンター購読（未認証でも読める）
  useEffect(() => {
    const unsub = subscribeLiveCount(setLiveCount);
    return unsub;
  }, []);

  // Googleログイン + モード指定
  const handleSelectMode = async (mode: Mode90) => {
    localStorage.setItem(NS90_MODE_KEY, mode);
    setLoadingMode(mode);
    try {
      const user = await signInWithGoogle();
      setUser(user);
      if (!incrementedRef.current) {
        incrementedRef.current = true;
        incrementLiveCount().catch(() => {});
      }
      onAuthenticated(mode);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'ログインに失敗しました');
    } finally {
      setLoadingMode(null);
    }
  };

  return (
    <div
      style={{
        minHeight: '100svh',
        display: 'flex',
        flexDirection: 'column',
        background: '#fff',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}
    >
      {/* ── ヘッダー ─────────────────────────────────────────────── */}
      <div style={{ textAlign: 'center', padding: '52px 24px 28px' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginBottom: 20 }}>
          <img
            src="/mascot.png"
            loading="lazy"
            alt="Fitingo"
            style={{ width: 40, height: 40, borderRadius: '50%', objectFit: 'cover', border: '2px solid #58CC02' }}
          />
          <span style={{ fontSize: 22, fontWeight: 900, color: '#58CC02', letterSpacing: '-0.5px' }}>
            Fitingo
          </span>
        </div>
        <h1
          style={{
            fontSize: 36,
            fontWeight: 900,
            color: '#1f1f1f',
            margin: 0,
            lineHeight: 1.2,
            letterSpacing: '-0.5px',
          }}
        >
          今度こそ、続く。
        </h1>
        <p style={{ fontSize: 15, color: '#888', marginTop: 10, marginBottom: 0, fontWeight: 600 }}>
          何を続けますか？ 5日間だけ試してみよう。
        </p>

        {/* ライブカウンター */}
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 7,
            marginTop: 14,
            padding: '6px 16px',
            borderRadius: 999,
            background: 'rgba(88,204,2,0.10)',
            border: '1.5px solid rgba(88,204,2,0.25)',
          }}
        >
          <span
            style={{
              width: 7, height: 7, borderRadius: '50%',
              background: '#58CC02',
              display: 'inline-block',
              flexShrink: 0,
              boxShadow: '0 0 0 3px rgba(88,204,2,0.22)',
            }}
          />
          <span style={{ fontSize: 12, fontWeight: 800, color: '#1f1f1f' }}>
            今日{liveCount > 0 ? ` ${liveCount.toLocaleString()} 人` : ''}が挑戦中
          </span>
        </div>
      </div>

      {/* ── アプリ内ブラウザ警告（LINE等） ───────────────────────── */}
      {inAppBrowser && (
        <div
          style={{
            maxWidth: 440,
            width: '100%',
            margin: '0 auto 14px',
            padding: '0 20px',
            boxSizing: 'border-box',
          }}
        >
          <div
            style={{
              borderRadius: 16,
              padding: 16,
              background: '#FFF7E6',
              border: '2px solid #FFD37A',
            }}
          >
            <p style={{ fontWeight: 900, fontSize: 14, color: '#1f1f1f', marginBottom: 4 }}>
              ⚠️ {IN_APP_BROWSER_LABEL[inAppBrowser]}内ではGoogleログインできません
            </p>
            <p style={{ fontSize: 12, color: '#888', fontWeight: 600, lineHeight: 1.5, marginBottom: inAppBrowser === 'line' ? 10 : 0 }}>
              Googleのポリシーにより、アプリ内ブラウザからのログインはブロックされます。
              {inAppBrowser === 'line'
                ? '下のボタンでブラウザを開いてください。'
                : '右上の「…」メニューなどから「ブラウザで開く」を選択してください。'}
            </p>
            {inAppBrowser === 'line' && (
              <button
                onClick={openInExternalBrowser}
                style={{
                  width: '100%',
                  padding: '10px 0',
                  borderRadius: 12,
                  background: '#58CC02',
                  border: 'none',
                  color: '#fff',
                  fontWeight: 900,
                  fontSize: 13,
                  cursor: 'pointer',
                  boxShadow: '0 3px 0 #46A302',
                }}
              >
                ブラウザで開く
              </button>
            )}
          </div>
        </div>
      )}

      {/* ── 4 モードボタン ───────────────────────────────────────── */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          gap: 14,
          padding: '0 20px',
          maxWidth: 440,
          width: '100%',
          margin: '0 auto',
          boxSizing: 'border-box',
        }}
      >
        {MODES.map((m) => {
          const isLoading = loadingMode === m.id;
          const isDisabled = loadingMode !== null || !!inAppBrowser;
          return (
            <div
              key={m.id}
              role="button"
              tabIndex={isDisabled ? -1 : 0}
              onClick={() => { if (!isDisabled) handleSelectMode(m.id); }}
              onKeyDown={(e) => {
                if (!isDisabled && (e.key === 'Enter' || e.key === ' ')) handleSelectMode(m.id);
              }}
              style={{
                width: '100%',
                padding: '18px 20px',
                borderRadius: 20,
                background: isLoading ? m.accentDark : `${m.accent}14`,
                border: `2px solid ${m.accent}`,
                cursor: isDisabled ? 'default' : 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 16,
                opacity: isDisabled && !isLoading ? 0.45 : 1,
                transition: 'all 0.15s ease',
                boxShadow: isLoading
                  ? `0 4px 0 ${m.accentDark}`
                  : `0 3px 0 ${m.accent}44`,
                textAlign: 'left',
              }}
            >
              <span
                style={{
                  fontSize: 36, width: 52, height: 52,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  borderRadius: '50%',
                  background: isLoading ? 'rgba(255,255,255,0.18)' : `${m.accent}18`,
                  flexShrink: 0,
                }}
              >
                {m.emoji}
              </span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 21, fontWeight: 900, color: isLoading ? '#fff' : '#1f1f1f' }}>
                  {m.label}
                </div>
                <div style={{ fontSize: 13, fontWeight: 600, color: isLoading ? 'rgba(255,255,255,0.8)' : '#999', marginTop: 2 }}>
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
                    flexShrink: 0,
                  }}
                />
              ) : (
                /* ── iOS アプリで開くボタン（右側・シンプル表示）───────── */
                <button
                  onClick={(e) => { e.stopPropagation(); openIOS(m.id); }}
                  disabled={isDisabled}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    padding: '9px 14px',
                    borderRadius: 999,
                    background: m.accent,
                    border: 'none',
                    cursor: isDisabled ? 'default' : 'pointer',
                    boxShadow: `0 3px 0 ${m.accentDark}`,
                    color: '#fff',
                    fontWeight: 900,
                    fontSize: 13,
                    flexShrink: 0,
                    transition: 'opacity 0.15s ease',
                  }}
                  onMouseEnter={(e) => (e.currentTarget.style.opacity = '0.85')}
                  onMouseLeave={(e) => (e.currentTarget.style.opacity = '1')}
                >
                  <AppleLogo size={13} />
                  iOS
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* ── フッター ─────────────────────────────────────────────── */}
      <p
        style={{
          textAlign: 'center',
          fontSize: 12,
          color: '#bbb',
          fontWeight: 600,
          padding: '20px 24px 36px',
          margin: 0,
        }}
      >
        5日続けると全機能が解放されます
      </p>

      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
};
