import { useEffect, useState } from 'react';
import { onAuthChange, getExercises, getUserProfile } from './services/firebase';
import { useAppStore } from './store/appStore';
import { LoginView } from './components/LoginView';
import { DashboardView } from './components/DashboardView';
import { ExerciseTrackerView } from './components/ExerciseTrackerView';
import { WeeklyGoalView } from './components/WeeklyGoalView';
import { HistoryView } from './components/HistoryView';
import { signOutUser } from './services/firebase';

type View = 'login' | 'dashboard' | 'tracker' | 'weekly' | 'history';

function App() {
  const user = useAppStore((state) => state.user);
  const setUser = useAppStore((state) => state.setUser);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setExercises = useAppStore((state) => state.setExercises);
  const setLoading = useAppStore((state) => state.setLoading);

  const [currentView, setCurrentView] = useState<View>('login');
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const unsubscribe = onAuthChange(async (firebaseUser) => {
      setLoading(true);
      try {
        if (firebaseUser) {
          setUser(firebaseUser);
          const [profile, exercisesList] = await Promise.all([
            getUserProfile(firebaseUser.uid),
            getExercises(),
          ]);
          if (profile) setUserProfile(profile);
          setExercises(exercisesList);
          setCurrentView('dashboard');
        } else {
          setUser(null);
          setUserProfile(null);
          setCurrentView('login');
        }
      } catch (error) {
        console.error('Auth change error:', error);
      } finally {
        setLoading(false);
      }
    });
    return unsubscribe;
  }, [setUser, setUserProfile, setExercises, setLoading]);

  const handleSignOut = async () => {
    try {
      await signOutUser();
      setMenuOpen(false);
    } catch (error) {
      console.error('Sign out error:', error);
    }
  };

  const navigate = (view: View) => {
    setCurrentView(view);
    setMenuOpen(false);
  };

  return (
    <div className="min-h-screen bg-duo-gray-light">
      {user && (
        <nav className="bg-white sticky top-0 z-50" style={{ borderBottom: '2px solid #e5e5e5' }}>
          <div className="max-w-4xl mx-auto px-4 py-3 flex justify-between items-center">
            {/* Logo */}
            <button
              onClick={() => navigate('dashboard')}
              className="flex items-center gap-2 hover:opacity-80 transition-opacity"
            >
              <img src="/mascot.png" alt="DuoFit" className="w-9 h-9 rounded-full object-cover" />
              <span className="text-2xl font-black text-duo-green tracking-tight">DuoFit</span>
            </button>

            {/* Right side: Training shortcut + hamburger */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => navigate('tracker')}
                className={`px-4 py-2 rounded-xl font-extrabold text-sm transition-all ${
                  currentView === 'tracker'
                    ? 'bg-duo-green-light text-duo-green-dark'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
              >
                💪 トレーニング
              </button>

              {/* Hamburger */}
              <div className="relative">
                <button
                  onClick={() => setMenuOpen((o) => !o)}
                  className="w-10 h-10 flex flex-col items-center justify-center gap-1.5 rounded-xl hover:bg-duo-gray-light transition-all"
                  aria-label="メニュー"
                >
                  <span className="block w-5 h-0.5 bg-duo-dark rounded-full transition-all" />
                  <span className="block w-5 h-0.5 bg-duo-dark rounded-full transition-all" />
                  <span className="block w-5 h-0.5 bg-duo-dark rounded-full transition-all" />
                </button>

                {menuOpen && (
                  <>
                    {/* Backdrop */}
                    <div
                      className="fixed inset-0 z-40"
                      onClick={() => setMenuOpen(false)}
                    />
                    {/* Dropdown */}
                    <div
                      className="absolute right-0 top-12 z-50 w-44 rounded-2xl py-2 flex flex-col"
                      style={{ background: 'white', border: '2px solid #e5e5e5', boxShadow: '0 8px 24px rgba(0,0,0,0.12)' }}
                    >
                      {[
                        { view: 'dashboard' as View, icon: '🏠', label: 'ホーム' },
                        { view: 'tracker' as View, icon: '💪', label: 'トレーニング' },
                        { view: 'weekly' as View, icon: '🎯', label: '週間目標' },
                        { view: 'history' as View, icon: '📅', label: '履歴' },
                      ].map(({ view, icon, label }) => (
                        <button
                          key={view}
                          onClick={() => navigate(view)}
                          className={`flex items-center gap-3 px-4 py-3 text-left font-extrabold text-sm transition-all ${
                            currentView === view
                              ? 'text-duo-green bg-duo-green-light'
                              : 'text-duo-dark hover:bg-duo-gray-light'
                          }`}
                        >
                          <span>{icon}</span>
                          <span>{label}</span>
                        </button>
                      ))}
                      <div style={{ borderTop: '1.5px solid #e5e5e5', margin: '4px 0' }} />
                      <button
                        onClick={handleSignOut}
                        className="flex items-center gap-3 px-4 py-3 text-left font-extrabold text-sm text-duo-gray hover:text-duo-red hover:bg-red-50 transition-all"
                      >
                        <span>🚪</span>
                        <span>ログアウト</span>
                      </button>
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        </nav>
      )}

      <main>
        {currentView === 'login' && <LoginView />}
        {currentView === 'dashboard' && user && (
          <DashboardView
            onLogWorkout={() => navigate('tracker')}
            onWeeklyGoal={() => navigate('weekly')}
          />
        )}
        {currentView === 'tracker' && user && (
          <ExerciseTrackerView onSuccess={() => navigate('dashboard')} />
        )}
        {currentView === 'weekly' && user && (
          <WeeklyGoalView />
        )}
        {currentView === 'history' && user && (
          <HistoryView />
        )}
      </main>
    </div>
  );
}

export default App;
