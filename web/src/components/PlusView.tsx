import { useState } from 'react';

interface PlusViewProps {
  onBack: () => void;
}

interface Feature {
  icon: string;
  category: string;
  title: string;
  free: string | boolean;
  plus: string | boolean;
  plusNote?: string;
}

const FEATURES: Feature[] = [
  // 全般
  { icon: '🚫', category: '全般', title: '広告なし', free: false, plus: true },
  { icon: '⚙️', category: '全般', title: '全機能フルアクセス', free: false, plus: true },

  // FIT
  { icon: '🏃', category: 'FIT', title: 'アクティビティ記録', free: true, plus: true },
  { icon: '📊', category: 'FIT', title: '詳細アクティビティ分析', free: false, plus: true, plusNote: '※ AI機能はAPIキー設定が必要' },
  { icon: '🎯', category: 'FIT', title: '目標自動調整提案', free: false, plus: true, plusNote: '※ AI機能はAPIキー設定が必要' },

  // FOOD
  { icon: '🍽️', category: 'FOOD', title: '食事ログ記録', free: true, plus: true },
  { icon: '📸', category: 'FOOD', title: 'フォトログ AI 栄養解析', free: false, plus: true, plusNote: '※ AI機能はAPIキー設定が必要' },
  { icon: '📋', category: 'FOOD', title: '週次・月次 食事レポート', free: false, plus: true },

  // MIND（タブ全体がPlus限定）
  { icon: '🌙', category: 'MIND', title: '睡眠・マインドフル記録', free: false, plus: true },
  { icon: '✨', category: 'MIND', title: 'AI コーチングコメント', free: false, plus: true, plusNote: '※ AI機能はAPIキー設定が必要' },

  // BOOKS
  { icon: '📚', category: 'BOOKS', title: 'Kindle本をWebで全文読む', free: false, plus: true },
  { icon: '📲', category: 'BOOKS', title: '書籍のオフライン保存', free: false, plus: true },

  // TOMO
  { icon: '👥', category: 'TOMO', title: '友達追加', free: '3人まで', plus: '無制限' },
  { icon: '👁️', category: 'TOMO', title: 'フレンドフィード閲覧', free: '一部', plus: 'すべて' },

  // Apple Watch
  { icon: '⌚', category: 'Watch', title: 'Apple Watchアプリ', free: false, plus: true },
  { icon: '🏅', category: 'Watch', title: 'Watchモーション運動検出', free: false, plus: true },
  { icon: '📲', category: 'Watch', title: 'Watchウィジェット', free: false, plus: true },

  // カスタマイズ
  { icon: '🎨', category: 'カスタマイズ', title: 'スパイラルテーマ', free: '1種', plus: '10種以上' },
  { icon: '📱', category: 'カスタマイズ', title: 'Plusウィジェット', free: false, plus: true },
  { icon: '🔔', category: 'カスタマイズ', title: '時間帯リマインダー', free: '1スロット', plus: '全スロット' },
];

const CATEGORY_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  全般:     { bg: 'rgba(85,85,85,0.07)',   text: '#555555', border: 'rgba(85,85,85,0.18)' },
  FIT:      { bg: 'rgba(255,75,75,0.08)',  text: '#FF4B4B', border: 'rgba(255,75,75,0.2)' },
  FOOD:     { bg: 'rgba(88,204,2,0.08)',   text: '#58CC02', border: 'rgba(88,204,2,0.2)' },
  MIND:     { bg: 'rgba(150,71,232,0.08)', text: '#9247E8', border: 'rgba(150,71,232,0.2)' },
  BOOKS:    { bg: 'rgba(255,122,0,0.08)',  text: '#FF7A00', border: 'rgba(255,122,0,0.2)' },
  TOMO:     { bg: 'rgba(28,176,246,0.08)', text: '#1CB0F6', border: 'rgba(28,176,246,0.2)' },
  Watch:    { bg: 'rgba(51,51,51,0.07)',   text: '#333333', border: 'rgba(51,51,51,0.15)' },
  カスタマイズ: { bg: 'rgba(255,150,0,0.08)', text: '#FF9600', border: 'rgba(255,150,0,0.2)' },
};

const CATEGORIES = ['全般', 'FIT', 'FOOD', 'MIND', 'BOOKS', 'TOMO', 'Watch', 'カスタマイズ'];

const CellValue = ({ value }: { value: string | boolean }) => {
  if (value === true) {
    return <span style={{ color: '#FF8C00', fontSize: 15, fontWeight: 900 }}>✓</span>;
  }
  if (value === false) {
    return <span style={{ color: '#e0e0e0', fontSize: 18 }}>—</span>;
  }
  return <span style={{ color: '#FF8C00', fontSize: 11, fontWeight: 800 }}>{value}</span>;
};

const PlusBadge = ({ size = 24 }: { size?: number }) => (
  <div style={{
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    width: size, height: size, borderRadius: '50%',
    background: 'linear-gradient(135deg, #FFD700 0%, #FF8C00 100%)',
    color: '#fff', fontWeight: 900,
    fontSize: size * 0.6,
    boxShadow: '0 2px 6px rgba(255,140,0,0.35)',
    flexShrink: 0,
  }}>
    +
  </div>
);

export const PlusView = ({ onBack }: PlusViewProps) => {
  const [codeInput, setCodeInput] = useState('');
  const [codeStatus, setCodeStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const [showCode, setShowCode] = useState(false);

  const handleCodeSubmit = () => {
    setCodeStatus(codeInput.trim() === 'kfit5526' ? 'success' : 'error');
  };

  return (
    <div style={{ maxWidth: 640, margin: '0 auto', padding: '16px 16px 80px' }}>

      {/* 戻るボタン */}
      <button
        onClick={onBack}
        style={{
          display: 'flex', alignItems: 'center', gap: 6,
          color: '#58CC02', fontWeight: 800, fontSize: 14,
          background: 'none', border: 'none', cursor: 'pointer',
          padding: '8px 0', marginBottom: 12,
        }}
      >
        ← 戻る
      </button>

      {/* ヒーローセクション */}
      <div style={{
        background: 'linear-gradient(135deg, #FF8C00 0%, #FFD700 100%)',
        borderRadius: 20, padding: '28px 24px', marginBottom: 24,
        textAlign: 'center', position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', top: -20, right: -20,
          fontSize: 80, opacity: 0.15, pointerEvents: 'none',
        }}>👑</div>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 12 }}>
          <PlusBadge size={56} />
        </div>
        <h1 style={{
          color: '#fff', fontSize: 24, fontWeight: 900, margin: '0 0 8px',
          textShadow: '0 1px 4px rgba(0,0,0,0.15)',
        }}>
          Fitingo Plus
        </h1>
        <p style={{ color: 'rgba(255,255,255,0.9)', fontSize: 14, margin: '0 0 16px', lineHeight: 1.5 }}>
          FIT・FOOD・MIND を極める<br />パーソナルウェルネスコーチ
        </p>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'center', flexWrap: 'wrap' }}>
          <div style={{
            background: 'rgba(255,255,255,0.9)', borderRadius: 14, padding: '10px 20px',
            textAlign: 'center',
          }}>
            <div style={{ color: '#FF8C00', fontSize: 20, fontWeight: 900 }}>¥480</div>
            <div style={{ color: '#666', fontSize: 10, fontWeight: 700 }}>/ 月</div>
          </div>
          <div style={{
            background: 'rgba(255,255,255,0.9)', borderRadius: 14, padding: '10px 20px',
            textAlign: 'center', position: 'relative',
          }}>
            <div style={{
              position: 'absolute', top: -8, left: '50%', transform: 'translateX(-50%)',
              background: '#FF4B4B', color: '#fff', fontSize: 9, fontWeight: 900,
              padding: '2px 8px', borderRadius: 20, whiteSpace: 'nowrap',
            }}>おすすめ</div>
            <div style={{ color: '#FF8C00', fontSize: 20, fontWeight: 900 }}>¥3,800</div>
            <div style={{ color: '#666', fontSize: 10, fontWeight: 700 }}>/ 年（約34%お得）</div>
          </div>
        </div>
        <p style={{ color: 'rgba(255,255,255,0.8)', fontSize: 11, margin: '12px 0 0', fontWeight: 600 }}>
          🎁 7日間無料トライアル付き
        </p>
      </div>

      {/* Plus の恩恵ハイライト */}
      <h2 style={{ fontSize: 15, fontWeight: 900, color: '#333', margin: '0 0 12px 4px' }}>
        ✨ Plus になるとできること
      </h2>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 28 }}>
        {[
          { icon: '📊', title: 'AI 詳細分析',      desc: '毎日の活動をAIが解析しフィードバック。APIキー設定が必要。' },
          { icon: '📸', title: 'フォト栄養解析',    desc: '写真を撮るだけでカロリー・栄養を自動算出。APIキー設定が必要。' },
          { icon: '🌙', title: 'MIND タブ全解放',   desc: '睡眠・マインドフルネス分析とAIコーチングが使えるようになる。' },
          { icon: '📚', title: 'Kindle本を全文読む', desc: 'Web上でFitingo関連のKindle本を全て読める。' },
          { icon: '⌚', title: 'Apple Watchアプリ', desc: 'Watch専用アプリとモーション運動検出・ウィジェットが使える。' },
          { icon: '👥', title: '友達無制限',        desc: 'TOMOフィードで無制限にフレンドと交流できる。' },
        ].map((item) => (
          <div
            key={item.title}
            style={{
              background: '#fff', borderRadius: 14, padding: '14px 12px',
              boxShadow: '0 2px 8px rgba(0,0,0,0.06)',
              border: '1.5px solid rgba(255,140,0,0.15)',
            }}
          >
            <div style={{ fontSize: 22, marginBottom: 4 }}>{item.icon}</div>
            <div style={{ fontSize: 12, fontWeight: 800, color: '#333', marginBottom: 4 }}>{item.title}</div>
            <div style={{ fontSize: 10, color: '#888', lineHeight: 1.4 }}>{item.desc}</div>
          </div>
        ))}
      </div>

      {/* AI についての注意書き */}
      <div style={{
        background: 'rgba(28,176,246,0.08)', borderRadius: 12, padding: '12px 14px',
        marginBottom: 24, display: 'flex', gap: 8, alignItems: 'flex-start',
      }}>
        <span style={{ fontSize: 16, flexShrink: 0 }}>ℹ️</span>
        <div>
          <p style={{ margin: '0 0 4px', fontSize: 12, fontWeight: 800, color: '#1CB0F6' }}>AIについて</p>
          <p style={{ margin: 0, fontSize: 11, color: '#555', lineHeight: 1.5 }}>
            AI機能（栄養解析・コーチング・目標提案など）はPlusプランでご利用可能ですが、
            <strong>SETTINGS → LLM設定</strong> から別途APIキーを設定する必要があります。
          </p>
        </div>
      </div>

      {/* 機能比較テーブル */}
      <h2 style={{ fontSize: 15, fontWeight: 900, color: '#333', margin: '0 0 12px 4px' }}>
        📋 Free vs Plus 比較
      </h2>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 32 }}>
        {CATEGORIES.map((cat) => {
          const color = CATEGORY_COLORS[cat];
          const features = FEATURES.filter((f) => f.category === cat);
          return (
            <div key={cat} style={{
              background: '#fff', borderRadius: 14,
              overflow: 'hidden', boxShadow: '0 2px 8px rgba(0,0,0,0.05)',
            }}>
              {/* カテゴリヘッダー */}
              <div style={{
                background: color.bg, padding: '8px 14px',
                borderBottom: `1px solid ${color.border}`,
              }}>
                <span style={{ fontSize: 12, fontWeight: 900, color: color.text }}>{cat}</span>
              </div>
              {/* テーブルヘッダー */}
              <div style={{
                display: 'grid', gridTemplateColumns: '1fr 72px 88px',
                padding: '6px 14px', background: 'rgba(0,0,0,0.02)',
                borderBottom: '1px solid #f0f0f0',
              }}>
                <span style={{ fontSize: 10, fontWeight: 700, color: '#aaa' }}>機能</span>
                <span style={{ fontSize: 10, fontWeight: 700, color: '#aaa', textAlign: 'center' as const }}>Free</span>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                  <PlusBadge size={14} />
                  <span style={{ fontSize: 10, fontWeight: 800, color: '#FF8C00' }}>Plus</span>
                </div>
              </div>
              {/* 機能行 */}
              {features.map((f, i) => (
                <div
                  key={f.title}
                  style={{
                    display: 'grid', gridTemplateColumns: '1fr 72px 88px',
                    padding: '10px 14px', alignItems: 'center',
                    borderBottom: i < features.length - 1 ? '1px solid #f5f5f5' : 'none',
                  }}
                >
                  <div>
                    <span style={{ fontSize: 13, color: '#333', display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span style={{ fontSize: 14 }}>{f.icon}</span>
                      {f.title}
                    </span>
                    {f.plusNote && (
                      <span style={{ fontSize: 9, color: '#aaa', display: 'block', paddingLeft: 20 }}>
                        {f.plusNote}
                      </span>
                    )}
                  </div>
                  <div style={{ textAlign: 'center' as const }}>
                    <CellValue value={f.free} />
                  </div>
                  <div style={{ textAlign: 'center' as const }}>
                    <CellValue value={f.plus} />
                  </div>
                </div>
              ))}
            </div>
          );
        })}
      </div>

      {/* CTAセクション */}
      <div style={{
        background: 'linear-gradient(135deg, #fff8e7 0%, #fff3cd 100%)',
        borderRadius: 20, padding: '24px 20px', marginBottom: 24,
        border: '1.5px solid rgba(255,200,0,0.3)', textAlign: 'center',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 8 }}>
          <PlusBadge size={40} />
        </div>
        <h3 style={{ fontSize: 16, fontWeight: 900, color: '#FF8C00', margin: '0 0 6px' }}>
          iOSアプリからアップグレード
        </h3>
        <p style={{ fontSize: 12, color: '#888', margin: '0 0 12px', lineHeight: 1.5 }}>
          App Store 経由のサブスクリプションは<br />
          iOS アプリの 設定 → Plus から利用できます。
        </p>
        <div style={{
          background: 'rgba(255,140,0,0.1)', borderRadius: 10, padding: '10px 14px',
          fontSize: 11, color: '#FF8C00', fontWeight: 700,
        }}>
          📲 App Store に掲載準備中・まもなく公開予定
        </div>
      </div>

      {/* Plusコード */}
      <div style={{
        background: '#fff', borderRadius: 16, overflow: 'hidden',
        boxShadow: '0 2px 10px rgba(0,0,0,0.06)',
        border: '1px solid #f0f0f0', marginBottom: 16,
      }}>
        <button
          onClick={() => setShowCode(!showCode)}
          style={{
            width: '100%', padding: '14px 16px',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            background: 'none', border: 'none', cursor: 'pointer',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 16 }}>🔑</span>
            <span style={{ fontSize: 13, fontWeight: 800, color: '#333' }}>
              Plusコードで解放
            </span>
          </div>
          <span style={{ color: '#aaa', fontSize: 12 }}>{showCode ? '▲' : '▼'}</span>
        </button>

        {showCode && (
          <div style={{ padding: '0 16px 16px', borderTop: '1px solid #f5f5f5' }}>
            <p style={{ fontSize: 11, color: '#888', margin: '10px 0 8px' }}>
              コードをお持ちの場合は入力してください。
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                type="password"
                value={codeInput}
                onChange={(e) => { setCodeInput(e.target.value); setCodeStatus('idle'); }}
                placeholder="Plusコードを入力"
                style={{
                  flex: 1, padding: '10px 12px', borderRadius: 8,
                  border: `1.5px solid ${codeStatus === 'error' ? '#FF4B4B' : '#e5e5e5'}`,
                  fontSize: 13, outline: 'none',
                }}
              />
              <button
                onClick={handleCodeSubmit}
                disabled={!codeInput.trim()}
                style={{
                  padding: '10px 16px', borderRadius: 8,
                  background: codeInput.trim() ? '#FF8C00' : '#e5e5e5',
                  color: '#fff', fontWeight: 800, fontSize: 13,
                  border: 'none', cursor: codeInput.trim() ? 'pointer' : 'not-allowed',
                }}
              >
                解放
              </button>
            </div>
            {codeStatus === 'success' && (
              <p style={{ color: '#58CC02', fontSize: 12, fontWeight: 800, marginTop: 8 }}>
                ✅ Plusを解放しました！iOSアプリで機能をお楽しみください。
              </p>
            )}
            {codeStatus === 'error' && (
              <p style={{ color: '#FF4B4B', fontSize: 12, fontWeight: 700, marginTop: 8 }}>
                ❌ コードが正しくありません。
              </p>
            )}
          </div>
        )}
      </div>

      {/* 注記 */}
      <p style={{ fontSize: 10, color: '#bbb', textAlign: 'center', lineHeight: 1.6 }}>
        * サブスクリプションは iTunes/App Store アカウントで管理されます。<br />
        購入の確認は設定 →「Apple ID」から行えます。
      </p>
    </div>
  );
};
