import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged, User } from 'firebase/auth';
import { getFirestore, collection, addDoc, query, where, getDocs, getDoc, doc, setDoc, updateDoc, increment, Timestamp } from 'firebase/firestore';

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

// Exercise completion
export const recordExercise = async (userId: string, exerciseData: any) => {
  try {
    const docRef = await addDoc(
      collection(db, 'users', userId, 'completed-exercises'),
      {
        ...exerciseData,
        timestamp: new Date(),
      }
    );
    await updateDoc(doc(db, 'users', userId), {
      totalPoints: increment(exerciseData.points || 0),
      lastActiveDate: new Date(),
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
  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

  const q = query(
    collection(db, 'users', userId, 'completed-exercises'),
    where('timestamp', '>=', startOfDay),
    where('timestamp', '<=', endOfDay)
  );

  const querySnapshot = await getDocs(q);
  return querySnapshot.docs.map(d => ({
    id: d.id,
    ...(d.data() as Omit<CompletedExercise, 'id'>),
  }));
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
  for (let i = 1; i < days; i++) {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const label = i === 1 ? '昨日' : `${date.getMonth() + 1}/${date.getDate()}`;
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

// Get achievements
export const getAchievements = async (userId: string) => {
  const q = collection(db, 'users', userId, 'achievements');
  const querySnapshot = await getDocs(q);
  return querySnapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data()
  }));
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

// Get leaderboard
export const getLeaderboard = async (_period: string = 'week') => {
  const now = new Date();
  const weekNumber = Math.ceil((now.getTime() - new Date(now.getFullYear(), 0, 1).getTime()) / 86400000 / 7);
  const year = now.getFullYear();
  const leaderboardPeriod = `week-${year}-${String(weekNumber).padStart(2, '0')}`;

  const q = collection(db, 'leaderboards', leaderboardPeriod, 'entries');
  const querySnapshot = await getDocs(q);
  return querySnapshot.docs
    .map(doc => ({
      id: doc.id,
      ...doc.data()
    }))
    .sort((a: any, b: any) => a.rank - b.rank)
    .slice(0, 100);
};
