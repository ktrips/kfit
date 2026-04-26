import React from 'react';
import { signInWithGoogle } from '../services/firebase';
import { useAppStore } from '../store/appStore';

export const LoginView: React.FC = () => {
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
    <div className="min-h-screen bg-duo-gray-light flex flex-col items-center justify-center px-4">
      {/* Hero */}
      <div className="flex flex-col items-center mb-8 animate-bounce_in">
        <img
          src="/mascot.png"
          alt="DuoFit マスコット"
          className="w-40 h-40 object-cover rounded-full mb-4"
          style={{ boxShadow: '0 8px 0 #46A302', border: '4px solid #58CC02' }}
        />
        <h1 className="text-6xl font-black text-duo-green tracking-tight mb-1">DuoFit</h1>
        <p className="text-duo-dark font-bold text-xl">筋トレを、習慣に。毎日楽しく！</p>
      </div>

      {/* Feature pills */}
      <div className="flex flex-wrap gap-3 justify-center mb-10">
        {[
          { emoji: '🔥', label: 'ストリーク継続' },
          { emoji: '⭐', label: 'ポイント獲得' },
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
    </div>
  );
};
