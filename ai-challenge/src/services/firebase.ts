import { initializeApp } from 'firebase/app';
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signOut,
  onAuthStateChanged,
  type User,
} from 'firebase/auth';
import {
  getFirestore,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  query,
  orderBy,
  limit,
  getDocs,
  Timestamp,
} from 'firebase/firestore';
import type { GameProgress, LeaderboardEntry, DojoDayProgress, BuilderChallengeProgress } from '../types/challenge';

const firebaseConfig = {
  apiKey:            import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain:        import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId:         import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket:     import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId:             import.meta.env.VITE_FIREBASE_APP_ID,
};

const app = initializeApp(firebaseConfig, 'ai-challenge');
export const auth = getAuth(app);
export const db = getFirestore(app);

const provider = new GoogleAuthProvider();

// ── Auth ──────────────────────────────────────────────────────────────────────

export const signInWithGoogle = async (): Promise<User> => {
  const result = await signInWithPopup(auth, provider);
  const user = result.user;
  const ref = doc(db, 'ac-users', user.uid);
  const snap = await getDoc(ref);
  if (!snap.exists()) {
    await setDoc(ref, {
      uid: user.uid,
      username: user.displayName ?? 'Player',
      email: user.email,
      createdAt: Timestamp.now(),
      totalScore: 0,
      streak: 0,
      stage: 'dojo',
    });
  }
  return user;
};

export const signOutUser = () => signOut(auth);

export const onAuthChange = (cb: (u: User | null) => void) =>
  onAuthStateChanged(auth, cb);

// ── Progress ───────────────────────────────────────────────────────────────────

export async function loadProgress(uid: string): Promise<Partial<GameProgress> | null> {
  const snap = await getDoc(doc(db, 'ac-users', uid));
  if (!snap.exists()) return null;
  return snap.data() as Partial<GameProgress>;
}

export async function saveDojoProgress(uid: string, progress: DojoDayProgress[]): Promise<void> {
  await updateDoc(doc(db, 'ac-users', uid), { dojoProgress: progress });
}

export async function saveBuilderProgress(uid: string, progress: BuilderChallengeProgress[]): Promise<void> {
  await updateDoc(doc(db, 'ac-users', uid), { builderProgress: progress });
}

export async function saveScore(uid: string, totalScore: number, weeklyScore: number): Promise<void> {
  await updateDoc(doc(db, 'ac-users', uid), { totalScore });

  const weekId = getWeekId();
  await setDoc(
    doc(db, 'ac-leaderboards', weekId, 'entries', uid),
    { weeklyScore, updatedAt: Timestamp.now() },
    { merge: true },
  );
}

// ── Leaderboard ────────────────────────────────────────────────────────────────

export async function fetchLeaderboard(): Promise<LeaderboardEntry[]> {
  const weekId = getWeekId();
  const q = query(
    collection(db, 'ac-leaderboards', weekId, 'entries'),
    orderBy('weeklyScore', 'desc'),
    limit(20),
  );
  const snap = await getDocs(q);
  return snap.docs.map((d, i) => ({
    uid: d.id,
    username: (d.data().username as string) ?? 'Player',
    weeklyScore: (d.data().weeklyScore as number) ?? 0,
    weeklyTokens: (d.data().weeklyTokens as number) ?? 0,
    dojoComplete: (d.data().dojoComplete as boolean) ?? false,
    rank: i + 1,
  }));
}

function getWeekId(): string {
  const d = new Date();
  const year = d.getFullYear();
  const week = Math.ceil(
    ((d.getTime() - new Date(year, 0, 1).getTime()) / 86400000 + new Date(year, 0, 1).getDay() + 1) / 7,
  );
  return `${year}-W${String(week).padStart(2, '0')}`;
}
