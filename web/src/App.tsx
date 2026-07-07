import { useEffect, useState } from 'react';
import { onAuthChange, getExercises, getUserProfile, subscribeToUserProfile } from './services/firebase';
import { useAppStore } from './store/appStore';
import { LoginView } from './components/LoginView';
import { DashboardView } from './components/DashboardView';
import { ExerciseTrackerView } from './components/ExerciseTrackerView';
import { WeeklyGoalView } from './components/WeeklyGoalView';
import { HistoryView } from './components/HistoryView';
import { HelpView } from './components/HelpView';
import { WorkoutPlanView } from './components/WorkoutPlanView';
import { DailyWorkoutFlow } from './components/DailyWorkoutFlow';
import { SettingsView } from './components/SettingsView';
import { AchievementsView } from './components/AchievementsView';
import { LeaderboardView } from './components/LeaderboardView';
import TimeSlotGoals from './components/timeSlot/TimeSlotGoals';
import { IntakeView } from './components/IntakeView';
import { FoodView } from './components/FoodView';
import { DietGoalView } from './components/DietGoalView';
import { MindView } from './components/MindView';
import { signOutUser } from './services/firebase';
import { BooksLanding } from './components/books/BooksLanding';
import { BookViewer, BookId } from './components/books/BookViewer';
import { PlusView } from './components/PlusView';
import { ChallengeLP } from './components/challenge/ChallengeLP';

type View = 'login' | 'dashboard' | 'tracker' | 'weekly' | 'history' | 'help' | 'plan' | 'workout' | 'settings' | 'achievements' | 'leaderboard' | 'timeSlots' | 'intake' | 'food' | 'dietGoal' | 'mind' | 'books' | 'bookDetail' | 'premium' | 'challenge';

/** URL パスから初期ビューを判定する */
function getInitialViewFromPath(): { view: View; bookId?: BookId } {
  const path = window.location.pathname;
  if (path.startsWith('/privacy-policy')) {
    window.location.replace('https://fit.ktrips.net/privacy-policy/');
    return { view: 'login' };
  }
  // ?plus=1 パラメータ: iOSアプリのPlusユーザーがWebで全文読む際に付与される
  // localStorage に保存してセッション以降も有効にする
  const params = new URLSearchParams(window.location.search);
  if (params.get('plus') === '1') {
    localStorage.setItem('isPlus_secret', 'true');
    // クリーンなURLに書き換え（パラメータ除去）
    const cleanPath = window.location.pathname;
    window.history.replaceState({}, '', cleanPath);
  }
  if (path.startsWith('/books/apple-watch-diet')) return { view: 'bookDetail', bookId: 'apple-watch-diet' };
  if (path.startsWith('/books/cursor-claude-code-plus')) return { view: 'bookDetail', bookId: 'cursor-claude-code-plus' };
  if (path.startsWith('/books/cursor-claude-code')) return { view: 'bookDetail', bookId: 'cursor-claude-code' };
  if (path.startsWith('/books')) return { view: 'books' };
  if (path.startsWith('/challenge-90') || path.startsWith('/c90')) return { view: 'challenge' };
  return { view: 'login' };
}

function App() {
  const user = useAppStore((state) => state.user);
  const userProfile = useAppStore((state) => state.userProfile);
  const setUser = useAppStore((state) => state.setUser);
  const setUserProfile = useAppStore((state) => state.setUserProfile);
  const setExercises = useAppStore((state) => state.setExercises);
  const setLoading = useAppStore((state) => state.setLoading);

  // Plus 判定: Firestore の isPlus フィールド / Admin メール / localStorage Plusコード
  const ADMIN_EMAIL = 'kenichiyoshida13@gmail.com';
  const isPlus: boolean = !!(
    (userProfile as any)?.isPlus ||
    user?.email === ADMIN_EMAIL ||
    localStorage.getItem('isPlus_secret') === 'true'
  );

  const initial = getInitialViewFromPath();
  const [currentView, setCurrentView] = useState<View>(initial.view);
  const [selectedBookId, setSelectedBookId] = useState<BookId | undefined>(initial.bookId);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    let profileUnsub: (() => void) | null = null;

    const unsubscribe = onAuthChange(async (firebaseUser) => {
      profileUnsub?.();
      profileUnsub = null;
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
          // /books・/challenge-90 にいる場合はそのまま
          const { view: initView } = getInitialViewFromPath();
          if (!initView.startsWith('book') && initView !== 'challenge') {
            setCurrentView('dashboard');
          }
          // Real-time listener: Cloud Function updates totalPoints/streak after each exercise
          profileUnsub = subscribeToUserProfile(firebaseUser.uid, setUserProfile);
        } else {
          setUser(null);
          setUserProfile(null);
          // /books/* や /challenge-90 パスにいる場合はそのまま
          const { view } = getInitialViewFromPath();
          if (!view.startsWith('book') && view !== 'challenge') {
            setCurrentView('login');
          }
        }
      } catch (error) {
        console.error('Auth change error:', error);
      } finally {
        setLoading(false);
      }
    });
    return () => { unsubscribe(); profileUnsub?.(); };
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
    if (view === 'books') {
      window.history.pushState({}, '', '/books');
    } else if (view === 'challenge') {
      // パス維持（/challenge-90 でも /c90 でもそのまま）
      const curPath = window.location.pathname;
      if (!curPath.startsWith('/challenge-90') && !curPath.startsWith('/c90')) {
        window.history.pushState({}, '', '/c90');
      }
    } else if (view !== 'bookDetail') {
      window.history.pushState({}, '', '/');
    }
  };

  const openBook = (id: BookId) => {
    setSelectedBookId(id);
    setCurrentView('bookDetail');
  };

  return (
    <div className="min-h-screen bg-duo-gray-light">
      {user && (
        <nav className="bg-white sticky top-0 z-50" style={{ borderBottom: '2px solid #e5e5e5' }}>
          <div className="max-w-4xl mx-auto px-3 py-2 flex justify-between items-center gap-2">
            {/* Logo */}
            <button
              onClick={() => navigate('dashboard')}
              className="flex items-center gap-1.5 hover:opacity-80 transition-opacity shrink-0"
            >
              <img src="/mascot.png" alt="Fitingo" className="w-7 h-7 rounded-full object-cover" />
              <span className="text-lg font-black text-duo-green tracking-tight">Fitingo</span>
            </button>

            {/* Right side: Home + Plan + Log + hamburger */}
            <div className="flex items-center gap-1 flex-nowrap">
              <button
                onClick={() => navigate('dashboard')}
                className={`px-2 py-1.5 rounded-xl font-extrabold text-xs transition-all whitespace-nowrap ${
                  currentView === 'dashboard'
                    ? 'bg-duo-green-light text-duo-green-dark'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
                aria-label="ホーム"
              >
                🏠
              </button>
              <button
                onClick={() => navigate('plan')}
                className={`px-2.5 py-1.5 rounded-xl font-extrabold text-xs transition-all whitespace-nowrap ${
                  currentView === 'plan'
                    ? 'bg-duo-green-light text-duo-green-dark'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
              >
                📋 プラン
              </button>
              <button
                onClick={() => navigate('tracker')}
                className={`px-2.5 py-1.5 rounded-xl font-extrabold text-xs transition-all whitespace-nowrap ${
                  currentView === 'tracker'
                    ? 'bg-duo-green-light text-duo-green-dark'
                    : 'text-duo-gray hover:text-duo-dark hover:bg-duo-gray-light'
                }`}
              >
                📝 ログ
              </button>

              {/* Hamburger */}
              <div className="relative">
                <button
                  onClick={() => setMenuOpen((o) => !o)}
                  className="w-8 h-8 flex flex-col items-center justify-center gap-1 rounded-xl hover:bg-duo-gray-light transition-all"
                  aria-label="メニュー"
                >
                  <span className="block w-4 h-0.5 bg-duo-dark rounded-full transition-all" />
                  <span className="block w-4 h-0.5 bg-duo-dark rounded-full transition-all" />
                  <span className="block w-4 h-0.5 bg-duo-dark rounded-full transition-all" />
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
                        { view: 'dietGoal' as View, icon: '🎯', label: 'DIET GOAL' },
                        { view: 'intake' as View, icon: '🍽️', label: '食事・ドリンク' },
                        { view: 'plan' as View, icon: '📋', label: '今日のプラン' },
                        { view: 'tracker' as View, icon: '💪', label: 'トレーニング' },
                        { view: 'weekly' as View, icon: '🎯', label: '週間目標' },
                        { view: 'achievements' as View, icon: '🏆', label: 'アチーブメント' },
                        { view: 'leaderboard' as View, icon: '📊', label: 'ランキング' },
                        { view: 'history' as View, icon: '📅', label: '履歴' },
                        { view: 'help' as View, icon: '❓', label: 'ヘルプ' },
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
                      {/* Plus */}
                      <button
                        onClick={() => navigate('premium')}
                        className="flex items-center gap-3 px-4 py-3 text-left font-extrabold text-sm transition-all"
                        style={{
                          color: currentView === 'premium' ? '#FF8C00' : '#FF8C00',
                          background: currentView === 'premium' ? 'rgba(255,140,0,0.08)' : 'transparent',
                        }}
                      >
                        <span style={{
                          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                          width: 20, height: 20, borderRadius: '50%',
                          background: 'linear-gradient(135deg,#FFD700,#FF8C00)',
                          color: '#fff', fontSize: 11, fontWeight: 900,
                        }}>P</span>
                        <span>Plus にアップグレード ✦</span>
                      </button>
                      <div style={{ borderTop: '1.5px solid #e5e5e5', margin: '4px 0' }} />
                      {/* 設定 */}
                      <button
                        onClick={() => navigate('settings')}
                        className={`flex items-center gap-3 px-4 py-3 text-left font-extrabold text-sm transition-all ${
                          currentView === 'settings'
                            ? 'text-duo-green bg-duo-green-light'
                            : 'text-duo-dark hover:bg-duo-gray-light'
                        }`}
                      >
                        <span>⚙️</span>
                        <span>設定</span>
                      </button>
                      <div style={{ borderTop: '1.5px solid #e5e5e5', margin: '4px 0' }} />
                      <button
                        onClick={handleSignOut}
                        className="flex items-center gap-3 px-4 py-3 text-left font-extrabold text-sm text-duo-gray hover:text-duo-red hover:bg-red-50 transition-all"
                      >
                        <span>🚪</span>
                        <span>ログアウト</span>
                      </button>
                      <div className="px-4 py-2 text-center" style={{ borderTop: '1.5px solid #e5e5e5', marginTop: '4px' }}>
                        <p className="text-[10px] font-bold text-duo-gray">v0.5.0 · 2026-05-30</p>
                      </div>
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        </nav>
      )}

      <main>
        {/* ── 書籍ページ（ログイン不要・全画面） ── */}
        {currentView === 'books' && (
          <BooksLanding
            onSelectBook={openBook}
            onBackToApp={user ? () => navigate('dashboard') : undefined}
            isPlus={isPlus}
            isLoggedIn={!!user}
          />
        )}
        {currentView === 'bookDetail' && selectedBookId && (
          <BookViewer
            bookId={selectedBookId}
            onBack={() => navigate('books')}
            isPlus={isPlus}
          />
        )}
        {/* ── 90日再検査チャレンジ LP（ログイン不要・全画面） ── */}
        {currentView === 'challenge' && <ChallengeLP />}

        {currentView === 'login' && (
          <LoginView
            onOpenBooks={() => navigate('books')}
            onStartWorkout={() => navigate('workout')}
          />
        )}
        {currentView === 'dashboard' && user && (
          <DashboardView
            onStartWorkout={() => navigate('workout')}
            onLogWorkout={() => navigate('tracker')}
            onWeeklyGoal={() => navigate('weekly')}
            onWorkoutPlan={() => navigate('plan')}
            onDietGoal={() => navigate('dietGoal')}
          />
        )}
        {currentView === 'workout' && (
          <DailyWorkoutFlow onFinish={() => navigate(user ? 'dashboard' : 'login')} />
        )}
        {currentView === 'tracker' && user && (
          <ExerciseTrackerView
            onSuccess={() => navigate('dashboard')}
            onBack={() => navigate('dashboard')}
          />
        )}
        {currentView === 'weekly' && user && (
          <WeeklyGoalView />
        )}
        {currentView === 'history' && user && (
          <HistoryView />
        )}
        {currentView === 'help' && user && (
          <HelpView />
        )}
        {currentView === 'plan' && user && (
          <WorkoutPlanView />
        )}
        {currentView === 'settings' && user && (
          <SettingsView onNavigateToTimeSlots={() => navigate('timeSlots')} />
        )}
        {currentView === 'achievements' && user && (
          <AchievementsView />
        )}
        {currentView === 'leaderboard' && user && (
          <LeaderboardView />
        )}
        {currentView === 'timeSlots' && user && (
          <TimeSlotGoals />
        )}
        {currentView === 'intake' && user && (
          <IntakeView />
        )}
        {currentView === 'food' && user && (
          <FoodView />
        )}
        {currentView === 'dietGoal' && user && (
          <DietGoalView />
        )}
        {currentView === 'mind' && user && (
          <MindView />
        )}
        {currentView === 'premium' && user && (
          <PlusView onBack={() => navigate('dashboard')} />
        )}
      </main>

      {/* ── ログイン後フッター: BooksリンクとPrivacyポリシー ── */}
      {user && currentView !== 'books' && currentView !== 'bookDetail' && (
        <footer className="text-center py-4 border-t border-gray-100 flex flex-col items-center gap-2">
          <button
            onClick={() => navigate('books')}
            className="text-xs text-gray-400 hover:text-green-600 transition-colors font-semibold"
          >
            📚 Books — AppleWatch Diet / Cursor開発書を読む
          </button>
          <a
            href="https://fit.ktrips.net/privacy-policy/"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-gray-400 hover:text-green-600 transition-colors font-semibold"
          >
            🔐 プライバシーポリシー
          </a>
        </footer>
      )}

      {/* ── ログイン前フッター（未ログイン時も表示） ── */}
      {!user && currentView !== 'books' && currentView !== 'bookDetail' && (
        <footer className="text-center py-4">
          <a
            href="https://fit.ktrips.net/privacy-policy/"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-gray-400 hover:text-green-600 transition-colors font-semibold"
          >
            🔐 プライバシーポリシー
          </a>
        </footer>
      )}
    </div>
  );
}

export default App;
