import React, { useEffect, useState } from 'react';
import { onAuthChange, getExercises, getUserProfile } from './services/firebase';
import { useAppStore } from './store/appStore';
import { LoginView } from './components/LoginView';
import { DashboardView } from './components/DashboardView';
import { ExerciseTrackerView } from './components/ExerciseTrackerView';
import { LogOut } from 'lucide-react';
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
    <div className="min-h-screen bg-white">
      {user && (
        <nav className="bg-white border-b border-gray-200 shadow-sm">
          <div className="max-w-4xl mx-auto px-6 py-4 flex justify-between items-center">
            <h1 className="text-2xl font-bold text-blue-600">kfit</h1>
            <div className="flex gap-4">
              <button
                onClick={() => setCurrentView('dashboard')}
                className={`px-4 py-2 rounded-lg font-semibold transition ${
                  currentView === 'dashboard'
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-700 hover:bg-gray-100'
                }`}
              >
                Dashboard
              </button>
              <button
                onClick={() => setCurrentView('tracker')}
                className={`px-4 py-2 rounded-lg font-semibold transition ${
                  currentView === 'tracker'
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-700 hover:bg-gray-100'
                }`}
              >
                Log Workout
              </button>
              <button
                onClick={handleSignOut}
                className="px-4 py-2 text-red-600 hover:bg-red-50 rounded-lg font-semibold transition flex items-center gap-2"
              >
                <LogOut size={18} />
                Sign Out
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
