import { Trophy, Settings, LogOut, Zap } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';
import { signOutUser } from '../../services/firebase';

export function Header() {
  const { user, totalScore, streak, setView, setUser } = useGameStore();

  const handleSignOut = async () => {
    await signOutUser();
    setUser(null);
  };

  return (
    <header className="bg-white border-b border-gray-200 sticky top-0 z-50">
      <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between">
        <button
          onClick={() => setView('map')}
          className="flex items-center gap-2 hover:opacity-80 transition-opacity"
        >
          <div className="w-8 h-8 rounded-lg bg-brand flex items-center justify-center">
            <Zap className="w-5 h-5 text-white" />
          </div>
          <span className="text-xl font-black text-gray-900 tracking-tight">
            AI <span className="text-brand">Challenge</span>
          </span>
        </button>

        <div className="flex items-center gap-4">
          {streak > 0 && (
            <div className="flex items-center gap-1 text-orange-500 font-bold text-sm">
              <span>🔥</span>
              <span>{streak}日</span>
            </div>
          )}
          <div className="flex items-center gap-1 text-amber-500 font-bold text-sm">
            <Trophy className="w-4 h-4" />
            <span>{totalScore.toLocaleString()}pt</span>
          </div>

          {user && (
            <div className="flex items-center gap-2">
              {user.photoURL && (
                <img
                  src={user.photoURL}
                  alt={user.displayName ?? ''}
                  className="w-7 h-7 rounded-full border-2 border-brand-light"
                />
              )}
              <button
                onClick={() => setView('settings')}
                className="p-1.5 rounded-lg text-gray-500 hover:text-brand hover:bg-brand-light transition-colors"
                title="設定"
              >
                <Settings className="w-4 h-4" />
              </button>
              <button
                onClick={handleSignOut}
                className="p-1.5 rounded-lg text-gray-500 hover:text-red-500 hover:bg-red-50 transition-colors"
                title="ログアウト"
              >
                <LogOut className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
