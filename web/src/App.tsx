import React, { useEffect, useState } from 'react';
import { onAuthChange, getExercises, getUserProfile } from './services/firebase';
import { useAppStore } from './store/appStore';
import { LoginView } from './components/LoginView';
import { DashboardView } from './components/DashboardView';
import { ExerciseTrackerView } from './components/ExerciseTrackerView';
import { signOutUser } from './services/firebase';

type View = 'login' | 'dashboard' | 'tracker';

function App() {
  const user = useAppStore((state) => state.user);
  const setUser = useAppStore((state) => state.setUser);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setExercises = useAppStore((state) => state.setExercises);
  const setLoading = useAppStore((state) => state.setLoading);

  const [currentView, setCurrentView] = useState<View>('login');

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
    } catch (error) {
      console.error('Sign out error:', error);
    }
  };

  return (
    <div className="min-h-screen bg-duo-gray-light">
      {user && (
        <nav className="bg-white sticky top-0 z-50" style={{ borderBottom: '2px solid #e5e5e5' }}>
          <div className="max-w-4xl mx-auto px-4 py-3 flex justify-between items-center">
            {/* Logo */}
            <div className="flex items-center gap-2">
              <img src="/mascot.png" alt="DuoFit" className="w-9 h-9 rounded-full object-cover" />
              <span className="text-2xl font-black text-duo-green tracking-tight">DuoFit</span>
            </div>

            {/* Nav items */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setCurrentView('dashboard')}
                className={`px-4 py-2 rounded-xl font-extrabold text-sm transition-all ${
                  currentView === 'dashboard'
                    ? 'bg-duo-green-light text-duo-green-dark border-b-2 border-duo-green'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
              >
                🏠 ホーム
              </button>
              <button
                onClick={() => setCurrentView('tracker')}
                className={`px-4 py-2 rounded-xl font-extrabold text-sm transition-all ${
                  currentView === 'tracker'
                    ? 'bg-duo-green-light text-duo-green-dark border-b-2 border-duo-green'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
              >
                💪 トレーニング
              </button>
              <button
                onClick={handleSignOut}
                className="px-4 py-2 rounded-xl font-extrabold text-sm text-duo-gray hover:text-duo-red hover:bg-red-50 transition-all"
              >
                ログアウト
              </button>
            </div>
          </div>
        </nav>
      )}

      <main>
        {currentView === 'login' && <LoginView />}
        {currentView === 'dashboard' && user && (
          <DashboardView onLogWorkout={() => setCurrentView('tracker')} />
        )}
        {currentView === 'tracker' && user && (
          <ExerciseTrackerView onSuccess={() => setCurrentView('dashboard')} />
        )}
      </main>
    </div>
  );
}

export default App;
