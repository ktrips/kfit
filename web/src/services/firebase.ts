import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged, User } from 'firebase/auth';
import { getFirestore, collection, addDoc, query, where, orderBy, getDocs, getDoc, doc, setDoc, updateDoc, onSnapshot, Timestamp, increment } from 'firebase/firestore';

interface UserProfile {
  uid: string;
  email: string;
  username: string;
  totalPoints: number;
  streak: number;
  joinDate: Date;
  lastActiveDate: Date;
}

interface Exercise {
  id: string;
  name: string;
  basePoints: number;
  difficulty: string;
  muscleGroups: string[];
}

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);

// Firestoreキャッシュ設定（パフォーマンス最適化）
import { enableIndexedDbPersistence } from 'firebase/firestore';
enableIndexedDbPersistence(db).catch((err) => {
  if (err.code === 'failed-precondition') {
    console.warn('Firestore persistence: Multiple tabs open');
  } else if (err.code === 'unimplemented') {
    console.warn('Firestore persistence: Not supported in this browser');
  }
});

// キャッシュマネージャー
const cache = new Map<string, { data: any; timestamp: number }>();
const CACHE_TTL = 30000; // 30秒

function getCachedData<T>(key: string): T | null {
  const cached = cache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.data as T;
  }
  return null;
}

function setCachedData<T>(key: string, data: T): void {
  cache.set(key, { data, timestamp: Date.now() });
}

function invalidateCache(pattern?: string): void {
  if (pattern) {
    for (const key of cache.keys()) {
      if (key.includes(pattern)) {
        cache.delete(key);
      }
    }
  } else {
    cache.clear();
  }
}

const googleProvider = new GoogleAuthProvider();

export const signInWithGoogle = async () => {
  try {
    const result = await signInWithPopup(auth, googleProvider);
    const user = result.user;

    const userRef = doc(db, 'users', user.uid);
    const userDoc = await getDoc(userRef);

    if (!userDoc.exists()) {
      await setDoc(userRef, {
        uid: user.uid,
        email: user.email,
        username: user.displayName || 'User',
        totalPoints: 0,
        streak: 0,
        joinDate: new Date(),
        lastActiveDate: new Date(),
      });
    }

    return user;
  } catch (error) {
    console.error('Google sign-in error:', error);
    throw error;
  }
};


export const signOutUser = async () => {
  try {
    await signOut(auth);
  } catch (error) {
    console.error('Sign-out error:', error);
    throw error;
  }
};

export const onAuthChange = (callback: (user: User | null) => void) => {
  return onAuthStateChanged(auth, callback);
};

const DEFAULT_EXERCISES = [
  { id: 'pushup', name: 'Push-up', basePoints: 2, difficulty: 'medium', muscleGroups: ['chest', 'triceps', 'shoulders'] },
  { id: 'squat', name: 'Squat', basePoints: 2, difficulty: 'medium', muscleGroups: ['quadriceps', 'glutes', 'hamstrings'] },
  { id: 'situp', name: 'Sit-up', basePoints: 1, difficulty: 'easy', muscleGroups: ['abs', 'core'] },
  { id: 'lunge', name: 'Lunge', basePoints: 2, difficulty: 'medium', muscleGroups: ['quadriceps', 'glutes', 'hamstrings'] },
  { id: 'burpee', name: 'Burpee', basePoints: 5, difficulty: 'hard', muscleGroups: ['full body'] },
  { id: 'plank', name: 'Plank (sec)', basePoints: 1, difficulty: 'medium', muscleGroups: ['core', 'abs', 'shoulders'] },
];

// Exercise operations
export const getExercises = async (): Promise<Exercise[]> => {
  const exercisesCollection = collection(db, 'exercises');
  const querySnapshot = await getDocs(exercisesCollection);

  if (querySnapshot.empty) {
    await Promise.all(
      DEFAULT_EXERCISES.map((exercise) =>
        setDoc(doc(exercisesCollection, exercise.id), exercise)
      )
    );
    return DEFAULT_EXERCISES;
  }

  return querySnapshot.docs.map(d => ({
    id: d.id,
    ...(d.data() as Omit<Exercise, 'id'>),
  }));
};

// User profile operations
export const getUserProfile = async (userId: string): Promise<UserProfile | null> => {
  const userRef = doc(db, 'users', userId);
  const userDoc = await getDoc(userRef);
  return userDoc.exists() ? (userDoc.data() as UserProfile) : null;
};

// Real-time listener — updates profile whenever Cloud Function writes totalPoints/streak
export const subscribeToUserProfile = (
  userId: string,
  callback: (profile: UserProfile) => void
): (() => void) => {
  return onSnapshot(doc(db, 'users', userId), (snap) => {
    if (snap.exists()) callback(snap.data() as UserProfile);
  });
};

// Daily goals operations
export const getDailyGoals = async (userId: string, date: string) => {
  const q = query(
    collection(db, 'users', userId, 'daily-goals'),
    where('date', '==', date)
  );
  const querySnapshot = await getDocs(q);
  return querySnapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data()
  }));
};

export const setDailyGoals = async (userId: string, date: string, goals: any[]) => {
  for (const goal of goals) {
    const goalRef = doc(db, 'users', userId, 'daily-goals', goal.id);
    await setDoc(goalRef, {
      ...goal,
      date,
      completedReps: 0,
      status: 'pending'
    });
  }
};

// Exercise completion — streak/points updated client-side as fallback
// (Cloud Functions will override if deployed)
export const recordExercise = async (userId: string, exerciseData: any) => {
  try {
    // キャッシュ無効化
    invalidateCache(`todayExercises:${userId}`);
    invalidateCache(`weeklyProgress:${userId}`);

    const now = new Date();
    const docRef = await addDoc(
      collection(db, 'users', userId, 'completed-exercises'),
      { ...exerciseData, timestamp: now }
    );

    // Client-side streak + points update（Cloud Functions が未デプロイでも動作する）
    const userRef = doc(db, 'users', userId);
    const userSnap = await getDoc(userRef);
    const profile = userSnap.data() || {};

    const today   = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    let newStreak = profile.streak || 0;

    if (profile.lastActiveDate) {
      const last    = profile.lastActiveDate instanceof Timestamp
        ? profile.lastActiveDate.toDate()
        : new Date(profile.lastActiveDate);
      const lastDay = new Date(last.getFullYear(), last.getMonth(), last.getDate());
      const diffDays = Math.round((today.getTime() - lastDay.getTime()) / 86400000);

      if (diffDays === 0) {
        // 今日すでに記録済み — streak はそのまま
      } else if (diffDays <= 3) {
        // 1〜2日の休息は許容（週2チートデイ）
        newStreak = (profile.streak || 0) + 1;
      } else {
        newStreak = 1; // streak リセット
      }
    } else {
      newStreak = 1; // 初回記録
    }

    const points = exerciseData.points || 0;

    await updateDoc(userRef, {
      streak: newStreak,
      totalPoints: increment(points),
      lastActiveDate: Timestamp.fromDate(now),
    });

    return docRef.id;
  } catch (error) {
    console.error('Error recording exercise:', error);
    throw error;
  }
};

interface CompletedExercise {
  id: string;
  exerciseName: string;
  reps: number;
  points: number;
  timestamp?: Date;
}

// Get completed exercises for today
export const getTodayExercises = async (userId: string): Promise<CompletedExercise[]> => {
  const cacheKey = `todayExercises:${userId}`;
  const cached = getCachedData<CompletedExercise[]>(cacheKey);
  if (cached) {
    return cached;
  }

  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

  const q = query(
    collection(db, 'users', userId, 'completed-exercises'),
    where('timestamp', '>=', startOfDay),
    where('timestamp', '<=', endOfDay)
  );

  const querySnapshot = await getDocs(q);
  const exercises = querySnapshot.docs.map(d => ({
    id: d.id,
    ...(d.data() as Omit<CompletedExercise, 'id'>),
  }));

  setCachedData(cacheKey, exercises);
  return exercises;
};

export interface DayExercises {
  date: string;
  label: string;
  exercises: CompletedExercise[];
  totalReps: number;
  totalPoints: number;
}

export const getRecentExercises = async (userId: string, days: number = 7): Promise<DayExercises[]> => {
  const now = new Date();
  const startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() - days + 1, 0, 0, 0, 0);
  const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

  const q = query(
    collection(db, 'users', userId, 'completed-exercises'),
    where('timestamp', '>=', startDate),
    where('timestamp', '<=', endOfToday)
  );
  const snapshot = await getDocs(q);

  const byDay: Record<string, CompletedExercise[]> = {};
  snapshot.docs.forEach(d => {
    const data = d.data();
    const ts: Date = data.timestamp?.toDate ? data.timestamp.toDate() : new Date(data.timestamp);
    const key = `${ts.getFullYear()}-${String(ts.getMonth() + 1).padStart(2, '0')}-${String(ts.getDate()).padStart(2, '0')}`;
    if (!byDay[key]) byDay[key] = [];
    byDay[key].push({ id: d.id, ...(data as Omit<CompletedExercise, 'id'>) });
  });

  const result: DayExercises[] = [];
  for (let i = 0; i < days; i++) {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const label = i === 0 ? '今日' : i === 1 ? '昨日' : `${date.getMonth() + 1}/${date.getDate()}`;
    const exercises = byDay[key] ?? [];
    if (exercises.length > 0) {
      result.push({
        date: key,
        label,
        exercises,
        totalReps: exercises.reduce((s, e) => s + (e.reps || 0), 0),
        totalPoints: exercises.reduce((s, e) => s + (e.points || 0), 0),
      });
    }
  }
  return result;
};

// ── Achievements ─────────────────────────────────────────────────────────────

export interface Achievement {
  id: string;
  name: string;
  description: string;
  emoji: string;
  tier: 'bronze' | 'silver' | 'gold' | 'platinum';
  earnedDate?: Date;
  progress?: number;
  target?: number;
}

export const ACHIEVEMENT_DEFINITIONS: Record<string, Omit<Achievement, 'id' | 'earnedDate'>> = {
  'early-bird-10': {
    name: 'Early Bird',
    description: '朝9時前に10回トレーニング',
    emoji: '🌅',
    tier: 'bronze',
    target: 10,
  },
  'early-bird-50': {
    name: 'Morning Champion',
    description: '朝9時前に50回トレーニング',
    emoji: '🌄',
    tier: 'silver',
    target: 50,
  },
  'form-master-50': {
    name: 'Form Master',
    description: '完璧なフォームで50回',
    emoji: '💎',
    tier: 'silver',
    target: 50,
  },
  'iron-will-30': {
    name: 'Iron Will',
    description: '30日連続トレーニング',
    emoji: '🔥',
    tier: 'gold',
    target: 30,
  },
  'iron-will-90': {
    name: 'Legend',
    description: '90日連続トレーニング',
    emoji: '👑',
    tier: 'platinum',
    target: 90,
  },
  'century-club': {
    name: 'Century Club',
    description: '1日で100回以上',
    emoji: '💯',
    tier: 'gold',
    target: 100,
  },
  'leaderboard-king': {
    name: 'Leaderboard King',
    description: '週間ランキング1位獲得',
    emoji: '🏆',
    tier: 'platinum',
    target: 1,
  },
  'first-workout': {
    name: 'First Step',
    description: '最初のトレーニング完了',
    emoji: '🎯',
    tier: 'bronze',
    target: 1,
  },
  'workout-10': {
    name: 'Consistent',
    description: '10回トレーニング完了',
    emoji: '💪',
    tier: 'bronze',
    target: 10,
  },
  'workout-100': {
    name: 'Dedicated',
    description: '100回トレーニング完了',
    emoji: '⚡',
    tier: 'silver',
    target: 100,
  },
  'workout-500': {
    name: 'Elite',
    description: '500回トレーニング完了',
    emoji: '🌟',
    tier: 'gold',
    target: 500,
  },
};

// Get achievements
export const getAchievements = async (userId: string): Promise<Achievement[]> => {
  const q = collection(db, 'users', userId, 'achievements');
  const querySnapshot = await getDocs(q);
  return querySnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      description: data.description,
      emoji: data.emoji,
      tier: data.tier,
      earnedDate: data.earnedDate?.toDate?.() ?? data.earnedDate,
      progress: data.progress,
      target: data.target,
    };
  });
};

// ── Weekly goals ─────────────────────────────────────────────────────────────

export interface WeeklyGoal {
  exerciseId: string;
  exerciseName: string;
  dailyReps: number;   // 1日の目標rep数
  targetReps: number;  // 週間目標 = dailyReps × 5
}

export interface WeeklyProgress {
  [exerciseId: string]: number;
}

function getWeekBounds(): { start: Date; end: Date } {
  const now = new Date();
  const day = now.getDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const start = new Date(now);
  start.setDate(now.getDate() + diffToMonday);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(start.getDate() + 6);
  end.setHours(23, 59, 59, 999);
  return { start, end };
}

export function getCurrentWeekId(): string {
  const { start } = getWeekBounds();
  return start.toISOString().split('T')[0]; // Monday's date, e.g. "2026-04-27"
}

export function getActiveDaysElapsed(): number {
  const day = new Date().getDay(); // Sun=0, Mon=1, ..., Sat=6
  const daysSinceMonday = day === 0 ? 6 : day - 1;
  return Math.min(daysSinceMonday + 1, 5);
}

export function getWeekLabel(): string {
  const { start, end } = getWeekBounds();
  const fmt = (d: Date) => `${d.getMonth() + 1}/${d.getDate()}`;
  return `${fmt(start)} 〜 ${fmt(end)}`;
}

export const getWeeklyGoals = async (userId: string): Promise<WeeklyGoal[]> => {
  const weekId = getCurrentWeekId();
  const snapshot = await getDoc(doc(db, 'users', userId, 'weekly-goals', weekId));
  if (!snapshot.exists()) return [];
  return (snapshot.data().goals as WeeklyGoal[]) ?? [];
};

export const setWeeklyGoals = async (userId: string, goals: WeeklyGoal[]): Promise<void> => {
  const weekId = getCurrentWeekId();
  await setDoc(doc(db, 'users', userId, 'weekly-goals', weekId), {
    weekId,
    goals,
    updatedAt: Timestamp.now(),
  });
};

export const getWeeklyProgress = async (userId: string): Promise<WeeklyProgress> => {
  const { start, end } = getWeekBounds();
  const q = query(
    collection(db, 'users', userId, 'completed-exercises'),
    where('timestamp', '>=', start),
    where('timestamp', '<=', end)
  );
  const snapshot = await getDocs(q);
  const progress: WeeklyProgress = {};
  snapshot.docs.forEach(d => {
    const data = d.data();
    const id = data.exerciseId as string;
    progress[id] = (progress[id] ?? 0) + (data.reps ?? 0);
  });
  return progress;
};

// ── Completed sets (1セット = DailyWorkoutFlow を1周完了) ─────────────────────

export interface SetExercise {
  exerciseId: string;
  exerciseName: string;
  reps: number;
  points: number;
}

export interface WeeklySetProgress {
  completedSets: number;
  exercises: Record<string, { reps: number; sets: number; exerciseName: string }>;
}

// セット構成の取得（iOS互換）
interface SetConfigExercise {
  exerciseId: string;
  exerciseName: string;
  targetReps: number;
}

const getSetConfiguration = async (userId: string): Promise<SetConfigExercise[]> => {
  const docRef = doc(db, 'users', userId, 'settings', 'set-configuration');
  const docSnap = await getDoc(docRef);

  if (docSnap.exists()) {
    const data = docSnap.data();
    return (data.exercises ?? []) as SetConfigExercise[];
  }

  // デフォルト構成
  return [
    { exerciseId: 'pushup', exerciseName: '腕立て伏せ', targetReps: 10 },
    { exerciseId: 'squat', exerciseName: 'スクワット', targetReps: 15 },
    { exerciseId: 'situp', exerciseName: '腹筋', targetReps: 10 },
  ];
};

// セットが有効か検証（各メニューが目標回数以上達成されているか）
const validateSetCompletion = (exercises: SetExercise[], config: SetConfigExercise[]): boolean => {
  for (const target of config) {
    const completed = exercises.find(e => e.exerciseId === target.exerciseId);
    if (!completed || completed.reps < target.targetReps) {
      console.warn(`⚠️ ${target.exerciseName}: ${completed?.reps ?? 0}/${target.targetReps} - 目標未達`);
      return false;
    }
  }
  return true;
};

export const recordCompletedSet = async (
  userId: string,
  exercises: SetExercise[]
): Promise<void> => {
  const now = new Date();

  // セット構成を取得して目標達成を確認
  const config = await getSetConfiguration(userId);
  const isValidSet = validateSetCompletion(exercises, config);

  // セットとしてカウントする場合のみ記録
  if (isValidSet) {
    await addDoc(collection(db, 'users', userId, 'completed-sets'), {
      timestamp: now,
      exercises,
      totalXP: exercises.reduce((s, e) => s + e.points, 0),
      totalReps: exercises.reduce((s, e) => s + e.reps, 0),
      isValidSet: true,
    });
    console.log('✅ Valid set recorded: All exercises met target reps');
  } else {
    console.warn('⚠️ Set not counted: Some exercises did not meet target reps');
  }
};

export const getWeeklySetProgress = async (userId: string): Promise<WeeklySetProgress> => {
  const { start, end } = getWeekBounds();
  const q = query(
    collection(db, 'users', userId, 'completed-sets'),
    where('timestamp', '>=', start),
    where('timestamp', '<=', end)
  );
  const snapshot = await getDocs(q);

  const exercises: WeeklySetProgress['exercises'] = {};
  snapshot.docs.forEach(d => {
    const data = d.data();
    (data.exercises ?? []).forEach((e: SetExercise) => {
      if (!exercises[e.exerciseId]) {
        exercises[e.exerciseId] = { reps: 0, sets: 0, exerciseName: e.exerciseName };
      }
      exercises[e.exerciseId].reps += e.reps;
      exercises[e.exerciseId].sets += 1;
    });
  });

  return { completedSets: snapshot.size, exercises };
};

// ── 個別セット記録（タイムスタンプ付き一覧） ────────────────────────────────

export interface CompletedSetRecord {
  id: string;
  timestamp: Date;
  exercises: SetExercise[];
  totalXP: number;
  totalReps: number;
}

/** 今週完了したセットを新しい順で取得 */
export const getWeeklySetLog = async (userId: string): Promise<CompletedSetRecord[]> => {
  const { start, end } = getWeekBounds();
  const q = query(
    collection(db, 'users', userId, 'completed-sets'),
    where('timestamp', '>=', start),
    where('timestamp', '<=', end),
    orderBy('timestamp', 'desc')
  );
  const snapshot = await getDocs(q);
  return snapshot.docs.map(d => {
    const data = d.data();
    const ts = data.timestamp instanceof Timestamp
      ? data.timestamp.toDate()
      : new Date(data.timestamp);
    return {
      id: d.id,
      timestamp: ts,
      exercises: data.exercises ?? [],
      totalXP: data.totalXP ?? 0,
      totalReps: data.totalReps ?? 0,
    };
  });
};

/** 今日完了したセット数を返す */
export const getTodaySetCount = async (userId: string): Promise<number> => {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
  const end   = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
  const q = query(
    collection(db, 'users', userId, 'completed-sets'),
    where('timestamp', '>=', start),
    where('timestamp', '<=', end)
  );
  const snapshot = await getDocs(q);
  return snapshot.size;
};

/** 今日完了したセット一覧を新しい順で取得 */
export const getTodaySetLog = async (userId: string): Promise<CompletedSetRecord[]> => {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
  const end   = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
  const q = query(
    collection(db, 'users', userId, 'completed-sets'),
    where('timestamp', '>=', start),
    where('timestamp', '<=', end),
    orderBy('timestamp', 'desc')
  );
  const snapshot = await getDocs(q);
  return snapshot.docs.map(d => {
    const data = d.data();
    const ts = data.timestamp instanceof Timestamp
      ? data.timestamp.toDate()
      : new Date(data.timestamp);
    return {
      id: d.id,
      timestamp: ts,
      exercises: data.exercises ?? [],
      totalXP: data.totalXP ?? 0,
      totalReps: data.totalReps ?? 0,
    };
  });
};

export const getDailySetGoal = async (userId: string): Promise<number> => {
  const weekId = getCurrentWeekId();
  const snap = await getDoc(doc(db, 'users', userId, 'weekly-goals', weekId));
  return snap.exists() ? (snap.data().dailySets ?? 2) : 2;
};

export const saveDailySetGoal = async (userId: string, dailySets: number): Promise<void> => {
  const weekId = getCurrentWeekId();
  await setDoc(
    doc(db, 'users', userId, 'weekly-goals', weekId),
    { weekId, dailySets, updatedAt: Timestamp.now() },
    { merge: true }
  );
};

// ── Leaderboard ──────────────────────────────────────────────────────────────

export interface LeaderboardEntry {
  id: string;
  userId: string;
  username: string;
  rank: number;
  points: number;
  workouts: number;
  streak: number;
}

// Get leaderboard
export const getLeaderboard = async (_period: string = 'week'): Promise<LeaderboardEntry[]> => {
  const now = new Date();
  const weekNumber = Math.ceil((now.getTime() - new Date(now.getFullYear(), 0, 1).getTime()) / 86400000 / 7);
  const year = now.getFullYear();
  const leaderboardPeriod = `week-${year}-${String(weekNumber).padStart(2, '0')}`;

  const q = collection(db, 'leaderboards', leaderboardPeriod, 'entries');
  const querySnapshot = await getDocs(q);
  return querySnapshot.docs
    .map(doc => ({
      id: doc.id,
      userId: doc.data().userId,
      username: doc.data().username,
      rank: doc.data().rank,
      points: doc.data().points,
      workouts: doc.data().workouts ?? 0,
      streak: doc.data().streak ?? 0,
    }))
    .sort((a, b) => a.rank - b.rank)
    .slice(0, 100);
};

// ── Daily Calorie Goal ────────────────────────────────────────────────────────

export interface DailyCalorieGoal {
  targetCalories: number;
  consumedCalories: number;
  percentAchieved: number;
}

/** 種目ごとのカロリー消費量（kcal/rep） */
const CALORIES_PER_REP: Record<string, number> = {
  'pushup': 0.5,
  'push-up': 0.5,
  'squat': 0.6,
  'situp': 0.3,
  'sit-up': 0.3,
  'lunge': 0.5,
  'burpee': 1.0,
  'plank': 0.1,
};

/** カロリー目標を取得（カスタム設定またはデフォルト） */
export const getCalorieTarget = async (userId: string): Promise<number> => {
  const settingsRef = doc(db, 'users', userId, 'settings', 'calorie-goal');
  const settingsSnap = await getDoc(settingsRef);

  if (settingsSnap.exists() && settingsSnap.data().target) {
    return settingsSnap.data().target;
  }

  // デフォルト: 週間目標から計算
  const weeklyGoals = await getWeeklyGoals(userId);
  if (weeklyGoals.length > 0) {
    const dailyTotalReps = weeklyGoals.reduce((sum, g) => sum + ((g as any).dailyReps ?? 10), 0);
    // 平均的な種目のカロリー消費率 0.5 kcal/rep で計算
    return Math.round(dailyTotalReps * 0.5);
  }

  // フォールバック: 500kcal
  return 500;
};

/** カロリー目標をカスタム設定 */
export const setCalorieTarget = async (userId: string, targetCalories: number): Promise<void> => {
  const settingsRef = doc(db, 'users', userId, 'settings', 'calorie-goal');
  await setDoc(settingsRef, {
    target: targetCalories,
    updatedAt: Timestamp.now(),
  });
};

/** 今日の目標カロリーと消費カロリーを取得 */
export const getDailyCalorieGoal = async (userId: string): Promise<DailyCalorieGoal> => {
  // カスタム目標または計算された目標を取得
  const targetCalories = await getCalorieTarget(userId);

  // 今日の運動記録からカロリー計算
  const todayExercises = await getTodayExercises(userId);
  const consumedCalories = Math.round(
    todayExercises.reduce((total, ex) => {
      const exerciseId = (ex as any).exerciseId?.toLowerCase() ?? '';
      const calorieRate = CALORIES_PER_REP[exerciseId] ?? 0.4;
      return total + (ex.reps ?? 0) * calorieRate;
    }, 0)
  );

  const percentAchieved = targetCalories > 0
    ? Math.round((consumedCalories / targetCalories) * 100)
    : 0;

  return {
    targetCalories,
    consumedCalories,
    percentAchieved,
  };
};
