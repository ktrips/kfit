import {
  addDoc,
  collection,
  doc,
  getDoc,
  getDocs,
  increment,
  orderBy,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';
import { db } from './firebase';
import type {
  DietGoalSettings,
  DrinkType,
  IntakeLog,
  IntakeSummary,
  MealType,
  MindfulnessSession,
  MindMetrics,
} from '../types/wellness';

function startOfToday(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
}

function endOfToday(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
}

function todayKey(): string {
  const today = startOfToday();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
}

function toDate(value: unknown): Date {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return new Date(value as string | number);
}

const MEAL_DEFAULTS: Record<MealType, { label: string; calories: number; protein: number; fat: number; carbs: number }> = {
  breakfast: { label: '朝食', calories: 400, protein: 20, fat: 12, carbs: 55 },
  lunch:     { label: '昼食', calories: 650, protein: 30, fat: 22, carbs: 82 },
  dinner:    { label: '夕食', calories: 750, protein: 35, fat: 28, carbs: 90 },
  snack:     { label: '間食', calories: 180, protein: 5,  fat: 8,  carbs: 22 },
};

const DRINK_DEFAULTS: Record<DrinkType, { label: string; waterMl: number; caffeineMg: number; alcoholGrams: number; calories: number; protein: number; fat: number; carbs: number }> = {
  water:   { label: '水',         waterMl: 250, caffeineMg: 0,  alcoholGrams: 0,  calories: 0,   protein: 0, fat: 0, carbs: 0  },
  coffee:  { label: 'コーヒー',   waterMl: 180, caffeineMg: 90, alcoholGrams: 0,  calories: 5,   protein: 0, fat: 0, carbs: 1  },
  alcohol: { label: 'アルコール', waterMl: 0,   caffeineMg: 0,  alcoholGrams: 20, calories: 140, protein: 0, fat: 0, carbs: 15 },
};

export function getMealDefaults(mealType: MealType) {
  return MEAL_DEFAULTS[mealType];
}

export function getDrinkDefaults(drinkType: DrinkType) {
  return DRINK_DEFAULTS[drinkType];
}

export async function recordMealIntake(
  userId: string,
  mealType: MealType,
  calories?: number,
  timeSlot: string = 'web'
): Promise<IntakeLog> {
  const defaults = MEAL_DEFAULTS[mealType];
  const timestamp = new Date();
  const payload = {
    type: 'meal',
    mealType,
    label: defaults.label,
    calories: calories ?? defaults.calories,
    waterMl: 0,
    caffeineMg: 0,
    alcoholGrams: 0,
    protein: defaults.protein,
    fat: defaults.fat,
    carbs: defaults.carbs,
    timeSlot,
    timestamp: Timestamp.fromDate(timestamp),
  };
  const ref = await addDoc(collection(db, 'users', userId, 'daily-intake'), payload);
  return {
    id: ref.id,
    type: 'meal',
    label: payload.label,
    calories: payload.calories,
    waterMl: 0,
    caffeineMg: 0,
    alcoholGrams: 0,
    protein: payload.protein,
    fat: payload.fat,
    carbs: payload.carbs,
    timeSlot,
    timestamp,
  };
}

export async function recordDrinkIntake(
  userId: string,
  drinkType: DrinkType,
  amount?: number,
  timeSlot: string = 'web'
): Promise<IntakeLog> {
  const defaults = DRINK_DEFAULTS[drinkType];
  const multiplier = amount && defaults.waterMl > 0 ? amount / defaults.waterMl : 1;
  const timestamp = new Date();
  const payload = {
    type: 'drink',
    drinkType,
    label: defaults.label,
    calories: Math.round(defaults.calories * multiplier),
    waterMl: drinkType === 'water' || drinkType === 'coffee' ? (amount ?? defaults.waterMl) : defaults.waterMl,
    caffeineMg: Math.round(defaults.caffeineMg * multiplier),
    alcoholGrams: defaults.alcoholGrams,
    protein: 0,
    fat: 0,
    carbs: defaults.carbs,
    timeSlot,
    timestamp: Timestamp.fromDate(timestamp),
  };
  const ref = await addDoc(collection(db, 'users', userId, 'daily-intake'), payload);
  return {
    id: ref.id,
    type: 'drink',
    label: payload.label,
    calories: payload.calories,
    waterMl: payload.waterMl,
    caffeineMg: payload.caffeineMg,
    alcoholGrams: payload.alcoholGrams,
    protein: 0,
    fat: 0,
    carbs: payload.carbs,
    timeSlot,
    timestamp,
  };
}

export async function getTodayIntakeSummary(userId: string): Promise<IntakeSummary> {
  const q = query(
    collection(db, 'users', userId, 'daily-intake'),
    where('timestamp', '>=', startOfToday()),
    where('timestamp', '<=', endOfToday()),
    orderBy('timestamp', 'desc')
  );
  const snapshot = await getDocs(q);
  const logs: IntakeLog[] = snapshot.docs.map(item => {
    const data = item.data();
    return {
      id: item.id,
      type: data.type,
      label: data.label ?? '記録',
      calories: data.calories ?? 0,
      waterMl: data.waterMl ?? 0,
      caffeineMg: data.caffeineMg ?? 0,
      alcoholGrams: data.alcoholGrams ?? 0,
      protein: data.protein ?? 0,
      fat: data.fat ?? 0,
      carbs: data.carbs ?? 0,
      timeSlot: data.timeSlot ?? 'web',
      timestamp: data.timestamp ? toDate(data.timestamp) : new Date(),
    };
  });

  return {
    calories: logs.reduce((sum, log) => sum + log.calories, 0),
    waterMl: logs.reduce((sum, log) => sum + log.waterMl, 0),
    caffeineMg: logs.reduce((sum, log) => sum + log.caffeineMg, 0),
    alcoholGrams: logs.reduce((sum, log) => sum + log.alcoholGrams, 0),
    protein: logs.reduce((sum, log) => sum + log.protein, 0),
    fat: logs.reduce((sum, log) => sum + log.fat, 0),
    carbs: logs.reduce((sum, log) => sum + log.carbs, 0),
    mealCount: logs.filter(log => log.type === 'meal').length,
    drinkCount: logs.filter(log => log.type === 'drink').length,
    logs,
  };
}

export const DEFAULT_DIET_GOAL: DietGoalSettings = {
  startDate: todayKey(),
  goalDate: todayKey(),
  startWeightKg: 70,
  startBodyFatPercent: 22,
  currentWeightKg: 68.7,
  currentBodyFatPercent: 21,
  goalWeightKg: 65,
  goalBodyFatPercent: 18,
  dailyIntakeKcalGoal: 2000,
  dailyBurnKcalGoal: 2300,
};

export async function getDietGoalSettings(userId: string): Promise<DietGoalSettings> {
  const snap = await getDoc(doc(db, 'users', userId, 'settings', 'diet-goal'));
  if (!snap.exists()) return DEFAULT_DIET_GOAL;
  return { ...DEFAULT_DIET_GOAL, ...(snap.data() as Partial<DietGoalSettings>) };
}

export async function saveDietGoalSettings(userId: string, settings: DietGoalSettings): Promise<void> {
  await setDoc(doc(db, 'users', userId, 'settings', 'diet-goal'), {
    ...settings,
    updatedAt: Timestamp.now(),
  }, { merge: true });
}

export const DEFAULT_MIND_METRICS: MindMetrics = {
  latestHeartRate: 0,
  latestHRV: 0,
  averageHeartRate: 0,
  averageHRV: 0,
  mindfulnessMinutes: 0,
  standHours: 0,
  steps: 0,
};

export async function getMindMetrics(userId: string): Promise<MindMetrics> {
  const snap = await getDoc(doc(db, 'users', userId, 'mind-metrics', todayKey()));
  if (!snap.exists()) return DEFAULT_MIND_METRICS;
  const data = snap.data();
  return {
    ...DEFAULT_MIND_METRICS,
    ...(data as Partial<MindMetrics>),
    updatedAt: data.updatedAt ? toDate(data.updatedAt) : undefined,
  };
}

export async function saveMindMetrics(userId: string, metrics: MindMetrics): Promise<void> {
  await setDoc(doc(db, 'users', userId, 'mind-metrics', todayKey()), {
    ...metrics,
    updatedAt: Timestamp.now(),
  }, { merge: true });
}

export async function recordMindfulnessSession(
  userId: string,
  type: 'meditation' | 'stretch',
  durationSeconds: number,
  xp: number,
): Promise<MindfulnessSession> {
  const now = new Date();
  const label = type === 'meditation' ? '1分瞑想' : '3分ストレッチ';
  const ref = await addDoc(collection(db, 'users', userId, 'mindfulness-sessions'), {
    type,
    label,
    durationSeconds,
    xp,
    timestamp: Timestamp.fromDate(now),
  });
  await setDoc(
    doc(db, 'users', userId, 'mind-metrics', todayKey()),
    { mindfulnessMinutes: increment(durationSeconds / 60) },
    { merge: true },
  );
  await updateDoc(doc(db, 'users', userId), { totalPoints: increment(xp) });
  return { id: ref.id, type, label, durationSeconds, xp, timestamp: now };
}

export async function getTodayMindfulnessSessions(userId: string): Promise<MindfulnessSession[]> {
  const q = query(
    collection(db, 'users', userId, 'mindfulness-sessions'),
    where('timestamp', '>=', startOfToday()),
    where('timestamp', '<=', endOfToday()),
    orderBy('timestamp', 'desc'),
  );
  const snapshot = await getDocs(q);
  return snapshot.docs.map(d => {
    const data = d.data();
    return {
      id: d.id,
      type: data.type as 'meditation' | 'stretch',
      label: data.label ?? '',
      durationSeconds: data.durationSeconds ?? 60,
      xp: data.xp ?? 10,
      timestamp: toDate(data.timestamp),
    };
  });
}
