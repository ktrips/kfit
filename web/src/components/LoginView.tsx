import React from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { signInWithGoogle } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const APP_STORE_URL = 'https://apps.apple.com/app/fitingo/id000000000';

interface LoginViewProps {
  onOpenBooks?: () => void;
}

export const LoginView: React.FC<LoginViewProps> = ({ onOpenBooks: _onOpenBooks }) => {
  const setUser = useAppStore((state) => state.setUser);
  const setError = useAppStore((state) => state.setError);

  const handleGoogleSignIn = async () => {
    try {
      const user = await signInWithGoogle();
      setUser(user);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'サインインに失敗しました');
    }
  };

  return (
    <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center px-4 py-10">

      {/* Hero */}
      <div className="flex flex-col items-center mb-8 animate-bounce_in">
        <div className="relative mb-4">
          <img
            src="/mascot.png"
            alt="Fitingo マスコット"
            className="w-40 h-40 rounded-full object-cover drop-shadow-2xl"
            style={{ border: '4px solid #58CC02', boxShadow: '0 8px 0 #46A302' }}
          />
          {/* Glow ring */}
          <div
            className="absolute inset-0 rounded-full -z-10 scale-110 opacity-30 blur-md"
            style={{ background: 'radial-gradient(circle, #FF9600, #FF4500)' }}
          />
        </div>
        <h1 className="text-6xl font-black text-duo-green tracking-tight mb-1">Fitingo</h1>
        <p className="text-duo-dark font-bold text-xl">筋トレを、習慣に。毎日楽しく！💪</p>
      </div>

      {/* Feature pills */}
      <div className="flex flex-wrap gap-3 justify-center mb-10">
        {[
          { emoji: '🔥', label: 'ストリーク継続' },
          { emoji: '⭐', label: 'ポイント獲得'  },
          { emoji: '🏆', label: '実績アンロック' },
          { emoji: '📊', label: '進捗トラッキング' },
        ].map(({ emoji, label }) => (
          <span
            key={label}
            className="bg-white font-extrabold text-duo-dark px-4 py-2 rounded-full text-sm"
            style={{ border: '2px solid #e5e5e5', boxShadow: '0 3px 0 #e5e5e5' }}
          >
            {emoji} {label}
          </span>
        ))}
      </div>

      {/* Login card */}
      <div className="duo-card p-8 w-full max-w-sm">
        <button
          onClick={handleGoogleSignIn}
          className="duo-btn-primary w-full flex items-center justify-center gap-3 text-lg"
        >
          <svg className="w-5 h-5 shrink-0" viewBox="0 0 24 24">
            <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
            <path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
            <path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
            <path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
          </svg>
          Googleではじめる
        </button>

        <p className="text-center text-duo-gray text-xs mt-5 font-semibold">
          サインインすることで利用規約・プライバシーポリシーに同意したものとみなされます。
        </p>
      </div>

      {/* Workout GIF preview */}
      <div
        className="w-full max-w-sm mt-6 overflow-hidden rounded-3xl"
        style={{ border: '3px solid #58CC02', boxShadow: '0 6px 0 #46A302' }}
      >
        <img
          src="/fitingo_workout.gif"
          alt="Fitingo workout preview"
          className="w-full object-cover block"
          style={{ maxHeight: '280px', objectPosition: 'center' }}
        />
      </div>

      {/* ── iOS アプリ QRコード ── */}
      <div className="w-full max-w-sm mt-8">
        <div className="bg-white rounded-2xl border-2 border-gray-200 p-5 flex items-center gap-4">
          <div className="shrink-0 p-1 bg-white rounded-xl border border-gray-100 shadow-sm">
            <QRCodeSVG
              value={APP_STORE_URL}
              size={80}
              bgColor="#ffffff"
              fgColor="#1a1a1a"
              level="M"
            />
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-black text-gray-800 text-sm mb-0.5">📱 iOSアプリをインストール</p>
            <p className="text-xs text-gray-500 mb-2 leading-snug">
              QRコードをカメラで読み取るか、App Store で「Fitingo」を検索
            </p>
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 bg-black text-white text-xs font-bold px-3 py-1.5 rounded-lg hover:bg-gray-900 transition-colors"
            >
              <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              App Store で開く
            </a>
          </div>
        </div>
      </div>

      {/* ── 関連情報 ── */}
      <div className="w-full max-w-sm mt-10">
        <p className="text-[10px] font-black text-duo-gray tracking-widest uppercase mb-3 px-1">関連情報</p>

        <div className="flex flex-col gap-3">

          {/* iOS アプリ */}
          <a
            href="https://apps.apple.com/app/fitingo/id000000000"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
            style={{ border: '2px solid #e5e5e5', boxShadow: '0 3px 0 #e5e5e5' }}
          >
            <div className="w-12 h-12 rounded-2xl bg-black flex items-center justify-center shrink-0">
              <svg className="w-7 h-7 text-white" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-black text-duo-dark text-sm">📱 Fitingo iOSアプリ</p>
              <p className="text-xs text-duo-gray font-semibold mt-0.5">Apple Watch連携・モーションセンサーで本格トレーニング</p>
              <p className="text-[10px] text-duo-gray mt-0.5">App Store でダウンロード</p>
            </div>
            <span className="text-duo-gray shrink-0">›</span>
          </a>

          {/* AppleWatch Diet 本 */}
          <a
            href="https://amzn.to/4eEsrPg"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
            style={{ border: '2px solid #C8F0D8', boxShadow: '0 3px 0 #A0D8B8' }}
          >
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 text-3xl"
              style={{ background: '#E8F8F0' }}>
              ⌚
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-black text-sm" style={{ color: '#2D8A50' }}>AppleWatch Diet Ultra2</p>
              <p className="text-xs text-duo-gray font-semibold mt-0.5">Apple Watchで痩せる100のメソッド</p>
              <p className="text-[10px] font-bold mt-0.5" style={{ color: '#E8A020' }}>📖 Kindle で読む</p>
            </div>
            <span className="text-duo-gray shrink-0">›</span>
          </a>

          {/* Cursor + Claude 本 */}
          <a
            href="https://amzn.to/4aYIyGj"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
            style={{ border: '2px solid #C8D8F8', boxShadow: '0 3px 0 #A0B8E8' }}
          >
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 text-3xl"
              style={{ background: '#EEF2FF' }}>
              📱
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-black text-sm" style={{ color: '#2D50A0' }}>Cursor + Claude で iOS アプリを作る</p>
              <p className="text-xs text-duo-gray font-semibold mt-0.5">週末だけで iPhone・Apple Watch アプリを個人開発</p>
              <p className="text-[10px] font-bold mt-0.5" style={{ color: '#E8A020' }}>📖 Kindle で読む</p>
            </div>
            <span className="text-duo-gray shrink-0">›</span>
          </a>

          {/* 収益化本 */}
          <a
            href="https://amzn.to/4aTY6LA"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-4 bg-white rounded-2xl p-4 hover:shadow-md active:scale-[0.98] transition-all"
            style={{ border: '2px solid #FFE4C8', boxShadow: '0 3px 0 #F0C898' }}
          >
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 text-3xl"
              style={{ background: '#FFF5EB' }}>
              💰
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-black text-sm" style={{ color: '#C05800' }}>個人開発アプリを収益化する方法</p>
              <p className="text-xs text-duo-gray font-semibold mt-0.5">Kindle出版・Plus課金・SNS拡散戦略を解説</p>
              <p className="text-[10px] font-bold mt-0.5" style={{ color: '#E8A020' }}>📖 Kindle で読む</p>
            </div>
            <span className="text-duo-gray shrink-0">›</span>
          </a>

        </div>
      </div>
    </div>
  );
};
