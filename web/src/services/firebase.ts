import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged, User } from 'firebase/auth';
import { getFirestore, collection, addDoc, query, where, getDocs, getDoc, doc, setDoc, updateDoc } from 'firebase/firestore';

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

// Exercise operations
export const getExercises = async () => {
  const exercisesCollection = collection(db, 'exercises');
  const querySnapshot = await getDocs(exercisesCollection);
  return querySnapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data()
  }));
};

// User profile operations
export const getUserProfile = async (userId: string) => {
  const userRef = doc(db, 'users', userId);
  const userDoc = await getDoc(userRef);
  return userDoc.exists() ? userDoc.data() : null;
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
    return docRef.id;
  } catch (error) {
    console.error('Error recording exercise:', error);
    throw error;
  }
};

// Get completed exercises for today
export const getTodayExercises = async (userId: string) => {
  const today = new Date().toISOString().split('T')[0];
  const startOfDay = new Date(`${today}T00:00:00Z`);
  const endOfDay = new Date(`${today}T23:59:59Z`);

  const q = query(
    collection(db, 'users', userId, 'completed-exercises'),
    where('timestamp', '>=', startOfDay),
    where('timestamp', '<=', endOfDay)
  );

  const querySnapshot = await getDocs(q);
  return querySnapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data()
  }));
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

// Get leaderboard
export const getLeaderboard = async (period: string = 'week') => {
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
