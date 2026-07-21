import {
  addDoc,
  collection,
  doc,
  DocumentData,
  getDoc,
  getDocs,
  increment,
  onSnapshot,
  orderBy,
  query,
  QuerySnapshot,
  setDoc,
  Timestamp,
  Unsubscribe,
  updateDoc,
  where,
} from 'firebase/firestore';
import { db } from './firebase';
import { markActiveToday } from './retentionService';
import { localDateKey } from '../utils/date';
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
  return localDateKey();
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

// ─────────────────────────────────────────────────────────────
// 摂取記録の Firestore パスは iOS（AuthenticationManager.swift）が正:
//   users/{uid}/daily-intake/meals/logs   { mealType, foodName?, calories, protein, fat, carbs, sugar, fiber, sodium, timestamp }
//   users/{uid}/daily-intake/water/logs   { amountMl, timestamp }
//   users/{uid}/daily-intake/coffee/logs  { amountMl, caffeineMg, timestamp }
//   users/{uid}/daily-intake/alcohol/logs { alcoholType, amountMl, alcoholG, timestamp }
// 旧 Web 実装はフラットな users/{uid}/daily-intake/{autoId} に書いており
// iOS と同期しなかったため、iOS と同じ型別サブコレクションに統一する。
// ─────────────────────────────────────────────────────────────

function intakeLogs(userId: string, kind: 'meals' | 'water' | 'coffee' | 'alcohol') {
  return collection(db, 'users', userId, 'daily-intake', kind, 'logs');
}

const MEAL_LABELS: Record<string, string> = {
  breakfast: '朝食', lunch: '昼食', dinner: '夕食', snack: '間食',
};

export async function recordMealIntake(
  userId: string,
  mealType: MealType,
  calories?: number,
  timeSlot: string = 'web'
): Promise<IntakeLog> {
  const defaults = MEAL_DEFAULTS[mealType];
  const timestamp = new Date();
  const kcal = calories ?? defaults.calories;
  const ref = await addDoc(intakeLogs(userId, 'meals'), {
    mealType,
    calories: kcal,
    protein: defaults.protein,
    fat: defaults.fat,
    carbs: defaults.carbs,
    sugar: 0,
    fiber: 0,
    sodium: 0,
    timestamp: Timestamp.fromDate(timestamp),
  });
  void markActiveToday(userId); // 継続コホート計測
  return {
    id: ref.id,
    type: 'meal',
    label: defaults.label,
    calories: kcal,
    waterMl: 0,
    caffeineMg: 0,
    alcoholGrams: 0,
    protein: defaults.protein,
    fat: defaults.fat,
    carbs: defaults.carbs,
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
  const timestamp = new Date();
  const amountMl = amount ?? defaults.waterMl;
  const multiplier = defaults.waterMl > 0 ? amountMl / defaults.waterMl : 1;

  let refId: string;
  if (drinkType === 'water') {
    refId = (await addDoc(intakeLogs(userId, 'water'), {
      amountMl,
      timestamp: Timestamp.fromDate(timestamp),
    })).id;
  } else if (drinkType === 'coffee') {
    refId = (await addDoc(intakeLogs(userId, 'coffee'), {
      amountMl,
      caffeineMg: Math.round(defaults.caffeineMg * multiplier),
      timestamp: Timestamp.fromDate(timestamp),
    })).id;
  } else {
    // アルコール（既定はビール1杯 350ml 相当）
    refId = (await addDoc(intakeLogs(userId, 'alcohol'), {
      alcoholType: 'beer',
      amountMl: amountMl > 0 ? amountMl : 350,
      alcoholG: defaults.alcoholGrams,
      timestamp: Timestamp.fromDate(timestamp),
    })).id;
  }

  void markActiveToday(userId); // 継続コホート計測
  return {
    id: refId,
    type: 'drink',
    label: defaults.label,
    calories: Math.round(defaults.calories * multiplier),
    waterMl: amountMl,
    caffeineMg: drinkType === 'coffee' ? Math.round(defaults.caffeineMg * multiplier) : 0,
    alcoholGrams: drinkType === 'alcohol' ? defaults.alcoholGrams : 0,
    protein: 0,
    fat: 0,
    carbs: defaults.carbs,
    timeSlot,
    timestamp,
  };
}

type IntakeKind = 'meals' | 'water' | 'coffee' | 'alcohol';

function todayIntakeQuery(userId: string, kind: IntakeKind) {
  return query(
    intakeLogs(userId, kind),
    where('timestamp', '>=', startOfToday()),
    where('timestamp', '<=', endOfToday()),
    orderBy('timestamp', 'desc')
  );
}

function buildIntakeSummary(
  mealSnap: QuerySnapshot<DocumentData> | undefined,
  waterSnap: QuerySnapshot<DocumentData> | undefined,
  coffeeSnap: QuerySnapshot<DocumentData> | undefined,
  alcoholSnap: QuerySnapshot<DocumentData> | undefined,
): IntakeSummary {
  const logs: IntakeLog[] = [];

  mealSnap?.docs.forEach(item => {
    const data = item.data();
    logs.push({
      id: item.id,
      type: 'meal',
      label: (data.foodName as string) || MEAL_LABELS[data.mealType as string] || '食事',
      calories: data.calories ?? 0,
      waterMl: 0,
      caffeineMg: 0,
      alcoholGrams: 0,
      protein: data.protein ?? 0,
      fat: data.fat ?? 0,
      carbs: data.carbs ?? 0,
      timeSlot: 'meal',
      timestamp: data.timestamp ? toDate(data.timestamp) : new Date(),
    });
  });
  waterSnap?.docs.forEach(item => {
    const data = item.data();
    logs.push({
      id: item.id, type: 'drink', label: '水',
      calories: 0, waterMl: data.amountMl ?? 0, caffeineMg: 0, alcoholGrams: 0,
      protein: 0, fat: 0, carbs: 0, timeSlot: 'drink',
      timestamp: data.timestamp ? toDate(data.timestamp) : new Date(),
    });
  });
  coffeeSnap?.docs.forEach(item => {
    const data = item.data();
    logs.push({
      id: item.id, type: 'drink', label: 'コーヒー',
      calories: 0, waterMl: data.amountMl ?? 0, caffeineMg: data.caffeineMg ?? 0, alcoholGrams: 0,
      protein: 0, fat: 0, carbs: 0, timeSlot: 'drink',
      timestamp: data.timestamp ? toDate(data.timestamp) : new Date(),
    });
  });
  alcoholSnap?.docs.forEach(item => {
    const data = item.data();
    logs.push({
      id: item.id, type: 'drink', label: 'アルコール',
      // iOS 同様、アルコールの液量もドリンク合計（waterMl）に含める
      calories: 0, waterMl: data.amountMl ?? 0, caffeineMg: 0, alcoholGrams: data.alcoholG ?? 0,
      protein: 0, fat: 0, carbs: 0, timeSlot: 'drink',
      timestamp: data.timestamp ? toDate(data.timestamp) : new Date(),
    });
  });

  logs.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

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

export async function getTodayIntakeSummary(userId: string): Promise<IntakeSummary> {
  const [mealSnap, waterSnap, coffeeSnap, alcoholSnap] = await Promise.all([
    getDocs(todayIntakeQuery(userId, 'meals')),
    getDocs(todayIntakeQuery(userId, 'water')),
    getDocs(todayIntakeQuery(userId, 'coffee')),
    getDocs(todayIntakeQuery(userId, 'alcohol')),
  ]);
  return buildIntakeSummary(mealSnap, waterSnap, coffeeSnap, alcoholSnap);
}

/// 今日の摂取サマリーをリアルタイム購読する。
/// iOS側でHealthKit経由・アプリ内記録どちらでFirestoreに書き込まれても、
/// Webページを開き直さずに即座に最新値を反映する。
/// 呼び出し側は返り値の unsubscribe 関数を unmount 時に必ず呼ぶこと。
export function subscribeToTodayIntakeSummary(
  userId: string,
  callback: (summary: IntakeSummary) => void,
): Unsubscribe {
  const kinds: IntakeKind[] = ['meals', 'water', 'coffee', 'alcohol'];
  const snapshots: Partial<Record<IntakeKind, QuerySnapshot<DocumentData>>> = {};
  const settledKinds = new Set<IntakeKind>(); // 受信済み or エラー済み（空扱い）

  const emit = () => {
    // 初回は4種すべてが受信 or エラーで確定するまで待ってから呼ぶ（ちらつき防止）。
    // エラーの種類は snapshots が未設定のまま（=空扱い）で buildIntakeSummary に渡る。
    if (settledKinds.size < kinds.length) return;
    callback(buildIntakeSummary(
      snapshots.meals, snapshots.water, snapshots.coffee, snapshots.alcohol,
    ));
  };

  const unsubscribers = kinds.map(kind =>
    onSnapshot(
      todayIntakeQuery(userId, kind),
      snap => {
        snapshots[kind] = snap;
        settledKinds.add(kind);
        emit();
      },
      error => {
        // Firestoreエラー（権限拒否・オフライン等）でも他の3種の表示をブロックしない。
        // このkindは空扱いとして確定させ、ローディングが無限に続くのを防ぐ。
        console.error(`[wellnessService] intake subscription error (${kind}):`, error);
        settledKinds.add(kind);
        emit();
      }
    )
  );

  return () => unsubscribers.forEach(unsub => unsub());
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
  void markActiveToday(userId); // 継続コホート計測
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
