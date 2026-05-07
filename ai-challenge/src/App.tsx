import { useEffect } from 'react';
import { onAuthChange } from './services/firebase';
import { useGameStore } from './store/gameStore';
import { Header } from './components/challenge/Header';
import { LoginView } from './components/challenge/LoginView';
import { WorldMap } from './components/challenge/WorldMap';
import { DojoChallenge } from './components/challenge/DojoChallenge';
import { BuilderChallenge } from './components/challenge/BuilderChallenge';
import { ResultsView } from './components/challenge/ResultsView';
import { Leaderboard } from './components/challenge/Leaderboard';
import { ApiKeySettings } from './components/challenge/ApiKeySettings';

export default function App() {
  const {
    view,
    user,
    setUser,
    lastAttempt,
    selectedDojoDay,
    resetSprintIfExpired,
    resetWeeklyIfExpired,
    setView,
    goToDojo,
  } = useGameStore();

  useEffect(() => {
    const unsub = onAuthChange((u) => setUser(u));
    return unsub;
  }, [setUser]);

  useEffect(() => {
    resetSprintIfExpired();
    resetWeeklyIfExpired();
    const id = setInterval(() => {
      resetSprintIfExpired();
      resetWeeklyIfExpired();
    }, 60_000);
    return () => clearInterval(id);
  }, [resetSprintIfExpired, resetWeeklyIfExpired]);

  if (!user) return <LoginView />;

  return (
    <div className="min-h-screen bg-gray-50">
      {view !== 'login' && <Header />}
      <main>
        {view === 'map' && <WorldMap />}
        {view === 'dojo' && <DojoChallenge />}
        {view === 'builder' && <BuilderChallenge />}
        {view === 'results' && lastAttempt && selectedDojoDay && (
          <ResultsView
            attempt={lastAttempt}
            day={selectedDojoDay}
            onRetry={() => goToDojo(selectedDojoDay)}
            onNext={() => {
              const next = selectedDojoDay + 1;
              if (next <= 7) goToDojo(next);
              else setView('map');
            }}
            onMap={() => setView('map')}
          />
        )}
        {view === 'leaderboard' && <Leaderboard />}
        {view === 'settings' && <ApiKeySettings />}
      </main>
    </div>
  );
}
