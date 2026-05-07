import { useState } from 'react';
import { Trophy, Clock, TrendingUp } from 'lucide-react';
import { signInWithGoogle } from '../../services/firebase';
import { useGameStore } from '../../store/gameStore';

export function LoginView() {
  const { setUser } = useGameStore();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async () => {
    setLoading(true);
    setError('');
    try {
      const user = await signInWithGoogle();
      setUser(user);
    } catch (e) {
      setError('ログインに失敗しました。もう一度お試しください。');
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-red-50 via-white to-rose-50 flex flex-col items-center justify-center px-4">
      <div className="max-w-md w-full">
        {/* Logo */}
        <div className="text-center mb-10">
          <img
            src="/icon.svg"
            alt="AiLingo"
            className="w-20 h-20 mx-auto mb-4 drop-shadow-lg"
          />
          <h1 className="text-4xl font-black text-gray-900 mb-1">
            Ai<span className="text-red-500">Lingo</span>
          </h1>
          <p className="text-red-400 font-semibold text-sm mb-2">アイリンゴ</p>
          <p className="text-gray-500 text-sm leading-relaxed">
            Claudeを効率的に使いこなす技術を<br />ゲーム感覚で習得しよう
          </p>
        </div>

        {/* Feature pills */}
        <div className="grid grid-cols-3 gap-3 mb-8">
          {[
            { icon: <Trophy className="w-4 h-4" />, label: 'スコア競争', color: 'text-amber-500 bg-amber-50' },
            { icon: <Clock className="w-4 h-4" />, label: '5時間制限', color: 'text-blue-500 bg-blue-50' },
            { icon: <TrendingUp className="w-4 h-4" />, label: '難易度別', color: 'text-emerald-500 bg-emerald-50' },
          ].map(({ icon, label, color }) => (
            <div key={label} className={`flex flex-col items-center gap-1.5 rounded-xl p-3 ${color}`}>
              {icon}
              <span className="text-xs font-semibold">{label}</span>
            </div>
          ))}
        </div>

        {/* Stages preview */}
        <div className="bg-white rounded-2xl border border-gray-200 shadow-sm p-5 mb-6">
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-3">学習ステージ</p>
          {[
            { emoji: '🏯', name: 'DOJO', desc: 'ワンショットプロンプトの7つの型を習得', color: 'border-emerald-300 bg-emerald-50' },
            { emoji: '🏗️', name: 'BUILDER', desc: '難易度別アプリをセッション制限内で完成', color: 'border-blue-300 bg-blue-50' },
            { emoji: '🌟', name: 'CREATOR', desc: '自由設計で本格アプリを創る', color: 'border-purple-300 bg-purple-50' },
          ].map(({ emoji, name, desc, color }) => (
            <div key={name} className={`flex items-start gap-3 rounded-xl border p-3 mb-2 last:mb-0 ${color}`}>
              <span className="text-xl">{emoji}</span>
              <div>
                <p className="font-bold text-gray-800 text-sm">{name}</p>
                <p className="text-gray-500 text-xs">{desc}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Login button */}
        {error && (
          <p className="text-red-500 text-sm text-center mb-3">{error}</p>
        )}
        <button
          onClick={handleLogin}
          disabled={loading}
          className="w-full flex items-center justify-center gap-3 bg-white border-2 border-gray-200 rounded-2xl py-4 font-bold text-gray-700 hover:border-red-400 hover:text-red-500 transition-all shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {loading ? (
            <div className="w-5 h-5 border-2 border-red-500 border-t-transparent rounded-full animate-spin" />
          ) : (
            <svg className="w-5 h-5" viewBox="0 0 24 24">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
              <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
            </svg>
          )}
          {loading ? 'ログイン中...' : 'Googleでログイン'}
        </button>

        <p className="text-center text-xs text-gray-400 mt-4">
          ログインすることで利用規約に同意したものとみなします
        </p>
      </div>
    </div>
  );
}
