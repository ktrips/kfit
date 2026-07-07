import {
  doc,
  getDoc,
  setDoc,
  onSnapshot,
  Timestamp,
} from 'firebase/firestore';
import { db } from './firebase';
import {
  TimeSlot,
  TimeSlotGoal,
  TimeSlotProgress,
  DailyTimeSlotSettings,
  DailyTimeSlotProgress,
} from '../types/timeSlot';
import { localDateKey } from '../utils/date';
import { markActiveToday } from './retentionService';

const TIME_SLOT_GOALS_COLLECTION = 'time-slot-goals';
const TIME_SLOT_PROGRESS_COLLECTION = 'time-slot-progress';

// 日付を YYYY-MM-DD 形式の文字列に変換（ローカルタイムゾーン: iOS と同一キー）
function dateToString(date: Date): string {
  return localDateKey(date);
}

// デフォルトの目標を作成
function createDefaultGoal(timeSlot: TimeSlot): TimeSlotGoal {
  return {
    timeSlot,
    trainingGoal: timeSlot === TimeSlot.MIDNIGHT ? 0 : 1,
    mindfulnessGoal: timeSlot === TimeSlot.MIDNIGHT ? 0 : 1,
    stretchMinutesGoal: 0,
    logGoal: {
      mealRequired: timeSlot !== TimeSlot.MIDNIGHT,
      drinkRequired: timeSlot !== TimeSlot.MIDNIGHT,
      mealKcalGoal: timeSlot === TimeSlot.MIDNIGHT ? 0 : 500,
      drinkMlGoal: timeSlot === TimeSlot.MIDNIGHT ? 0 : 500,
      mindInputRequired: false
    },
    customActivities: [],
    reminderEnabled: false
  };
}

// デフォルトの実績を作成
function createDefaultProgress(timeSlot: TimeSlot): TimeSlotProgress {
  return {
    timeSlot,
    trainingCompleted: 0,
    mindfulnessCompleted: 0,
    stretchMinutesCompleted: 0,
    logProgress: {
      mealLogged: false,
      drinkLogged: false,
      mindInputLogged: false,
      mealKcalLogged: 0,
      drinkMlLogged: 0
    },
    completedActivityIds: [],
    lastUpdated: new Date()
  };
}

// ─────────────────────────────────────────────────────────────
// Firestore のワイヤ形式は iOS（TimeSlotManager.swift）が正。
//   goal:     { timeSlot, trainingGoal, mindfulnessGoal,
//               logGoal: { mealGoal:kcal, drinkGoal:ml, mindInputRequired },
//               stretchGoal: { enabled, stretchMinutes },
//               standGoal: { enabled, standMinutes },
//               customActivities: [{ id, name, emoji, isEnabled }],
//               reminderEnabled, reminderTime? }
//   progress: { timeSlot, trainingCompleted, mindfulnessCompleted,
//               logProgress: { mealLogged:kcal, drinkLogged:ml, mindInputLogged },
//               stretchSetsCompleted, standCompleted,
//               completedActivityIds, lastUpdated }
// Web 内部型との差分はここで相互変換し、Web が知らないフィールド
// （standGoal 等）は raw に保持して書き戻し時に消さない。
// ─────────────────────────────────────────────────────────────

// Firestore データから TimeSlotGoal に変換
function firestoreToGoal(data: any): TimeSlotGoal {
  const mealGoal = typeof data.logGoal?.mealGoal === 'number' ? data.logGoal.mealGoal : 500;
  const drinkGoal = typeof data.logGoal?.drinkGoal === 'number' ? data.logGoal.drinkGoal : 500;
  return {
    timeSlot: data.timeSlot as TimeSlot,
    trainingGoal: data.trainingGoal ?? 1,
    mindfulnessGoal: data.mindfulnessGoal ?? 1,
    stretchMinutesGoal: data.stretchGoal?.enabled
      ? (data.stretchGoal.stretchMinutes ?? 3)
      : (data.stretchMinutesGoal ?? 0),
    logGoal: {
      mealRequired: mealGoal > 0,
      drinkRequired: drinkGoal > 0,
      mealKcalGoal: mealGoal,
      drinkMlGoal: drinkGoal,
      mindInputRequired: data.logGoal?.mindInputRequired ?? false
    },
    customActivities: (data.customActivities || []).map((a: any) => ({
      id: a.id,
      title: a.title ?? a.name ?? '',
      emoji: a.emoji ?? '⭐',
      targetCount: a.targetCount ?? 1
    })),
    reminderEnabled: data.reminderEnabled || false,
    reminderTime: data.reminderTime
      ? (data.reminderTime as Timestamp).toDate()
      : undefined,
    raw: data
  };
}

// TimeSlotGoal から Firestore データに変換（iOS ワイヤ形式）
function goalToFirestore(goal: TimeSlotGoal): any {
  const raw = (goal.raw ?? {}) as Record<string, any>;
  const mealGoal = goal.logGoal.mealRequired ? (goal.logGoal.mealKcalGoal ?? 500) : 0;
  const drinkGoal = goal.logGoal.drinkRequired ? (goal.logGoal.drinkMlGoal ?? 500) : 0;
  const stretchMinutes = goal.stretchMinutesGoal ?? 0;
  const data: any = {
    ...raw, // standGoal など Web が扱わないフィールドを保持
    timeSlot: goal.timeSlot,
    trainingGoal: goal.trainingGoal,
    mindfulnessGoal: goal.mindfulnessGoal,
    logGoal: {
      mealGoal,
      drinkGoal,
      mindInputRequired: goal.logGoal.mindInputRequired
    },
    stretchGoal: {
      enabled: stretchMinutes > 0,
      stretchMinutes: stretchMinutes > 0 ? stretchMinutes : (raw.stretchGoal?.stretchMinutes ?? 3)
    },
    standGoal: raw.standGoal ?? { enabled: false, standMinutes: 20 },
    customActivities: (goal.customActivities || []).map(a => ({
      id: a.id,
      name: a.title,
      emoji: a.emoji,
      isEnabled: true
    })),
    reminderEnabled: goal.reminderEnabled
  };
  delete data.stretchMinutesGoal; // Web 旧形式のフィールドは書き込まない
  delete data.raw;

  if (goal.reminderTime) {
    data.reminderTime = Timestamp.fromDate(goal.reminderTime);
  } else {
    delete data.reminderTime;
  }

  return data;
}

// Firestore データから TimeSlotProgress に変換
function firestoreToProgress(data: any): TimeSlotProgress {
  // iOS は logProgress.mealLogged / drinkLogged を数値（kcal / ml）で保存する。
  // Web 旧形式（boolean）のデータも読めるよう両対応。
  const mealVal = data.logProgress?.mealLogged;
  const drinkVal = data.logProgress?.drinkLogged;
  const mealKcal = typeof mealVal === 'number' ? mealVal : (data.logProgress?.mealKcalLogged ?? 0);
  const drinkMl = typeof drinkVal === 'number' ? drinkVal : (data.logProgress?.drinkMlLogged ?? 0);
  return {
    timeSlot: data.timeSlot as TimeSlot,
    trainingCompleted: data.trainingCompleted || 0,
    mindfulnessCompleted: data.mindfulnessCompleted || 0,
    stretchMinutesCompleted: typeof data.stretchSetsCompleted === 'number'
      ? data.stretchSetsCompleted * 3 // iOS: 1セット=3分換算
      : (data.stretchMinutesCompleted || 0),
    logProgress: {
      mealLogged: mealKcal > 0 || mealVal === true,
      drinkLogged: drinkMl > 0 || drinkVal === true,
      mindInputLogged: data.logProgress?.mindInputLogged ?? false,
      mealKcalLogged: mealKcal,
      drinkMlLogged: drinkMl
    },
    completedActivityIds: data.completedActivityIds || [],
    lastUpdated: data.lastUpdated
      ? (data.lastUpdated as Timestamp).toDate()
      : new Date(),
    raw: data
  };
}

// TimeSlotProgress から Firestore データに変換（iOS ワイヤ形式）
function progressToFirestore(progress: TimeSlotProgress): any {
  const raw = (progress.raw ?? {}) as Record<string, any>;
  const mealKcal = progress.logProgress.mealKcalLogged
    ?? (progress.logProgress.mealLogged ? 1 : 0);
  const drinkMl = progress.logProgress.drinkMlLogged
    ?? (progress.logProgress.drinkLogged ? 1 : 0);
  const data: any = {
    ...raw, // standCompleted など Web が扱わないフィールドを保持
    timeSlot: progress.timeSlot,
    trainingCompleted: progress.trainingCompleted,
    mindfulnessCompleted: progress.mindfulnessCompleted,
    logProgress: {
      mealLogged: Math.round(mealKcal),
      drinkLogged: Math.round(drinkMl),
      mindInputLogged: progress.logProgress.mindInputLogged
    },
    stretchSetsCompleted: Math.round((progress.stretchMinutesCompleted ?? 0) / 3),
    standCompleted: raw.standCompleted ?? 0,
    completedActivityIds: progress.completedActivityIds || [],
    lastUpdated: Timestamp.fromDate(progress.lastUpdated)
  };
  delete data.stretchMinutesCompleted;
  delete data.raw;
  return data;
}

// 今日の時間帯別目標を取得
export async function getTodaySettings(
  userId: string
): Promise<DailyTimeSlotSettings> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dateStr = dateToString(today);

  const docRef = doc(
    db,
    'users',
    userId,
    TIME_SLOT_GOALS_COLLECTION,
    dateStr
  );
  const docSnap = await getDoc(docRef);

  if (docSnap.exists()) {
    const data = docSnap.data();
    const existingGoals = (data.goals || []).map(firestoreToGoal) as TimeSlotGoal[];
    const goals = Object.values(TimeSlot).map(slot =>
      existingGoals.find(goal => goal.timeSlot === slot) || createDefaultGoal(slot)
    );
    return { goals, date: today };
  } else {
    // デフォルト設定を作成
    const goals = Object.values(TimeSlot).map(createDefaultGoal);
    return { goals, date: today };
  }
}

// 今日の設定を保存
export async function saveTodaySettings(
  userId: string,
  settings: DailyTimeSlotSettings
): Promise<void> {
  const dateStr = dateToString(settings.date);
  const docRef = doc(
    db,
    'users',
    userId,
    TIME_SLOT_GOALS_COLLECTION,
    dateStr
  );

  const data = {
    goals: settings.goals.map(goalToFirestore),
    date: Timestamp.fromDate(settings.date)
  };

  await setDoc(docRef, data, { merge: true });
}

// 今日の時間帯別実績を取得
export async function getTodayProgress(
  userId: string
): Promise<DailyTimeSlotProgress> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dateStr = dateToString(today);

  const docRef = doc(
    db,
    'users',
    userId,
    TIME_SLOT_PROGRESS_COLLECTION,
    dateStr
  );
  const docSnap = await getDoc(docRef);

  if (docSnap.exists()) {
    const data = docSnap.data();
    const existingProgress = (data.progress || []).map(firestoreToProgress) as TimeSlotProgress[];
    const progress = Object.values(TimeSlot).map(slot =>
      existingProgress.find(item => item.timeSlot === slot) || createDefaultProgress(slot)
    );
    return { progress, date: today };
  } else {
    // デフォルト実績を作成
    const progress = Object.values(TimeSlot).map(createDefaultProgress);
    return { progress, date: today };
  }
}

// 今日の実績を保存
export async function saveTodayProgress(
  userId: string,
  progress: DailyTimeSlotProgress
): Promise<void> {
  const dateStr = dateToString(progress.date);
  const docRef = doc(
    db,
    'users',
    userId,
    TIME_SLOT_PROGRESS_COLLECTION,
    dateStr
  );

  const data = {
    progress: progress.progress.map(progressToFirestore),
    date: Timestamp.fromDate(progress.date)
  };

  await setDoc(docRef, data, { merge: true });

  // 継続コホート計測: 実績保存 = 何らかの活動を記録した日（1日1回のみ書き込み）
  void markActiveToday(userId);
}

// 今日の実績をリアルタイム購読する。
// iOS / Apple Watch で記録すると同じドキュメントが更新されるため、
// Web を開いたままでも進捗が即時反映される。戻り値は購読解除関数。
export function subscribeTodayProgress(
  userId: string,
  callback: (progress: DailyTimeSlotProgress) => void
): () => void {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dateStr = dateToString(today);
  const docRef = doc(db, 'users', userId, TIME_SLOT_PROGRESS_COLLECTION, dateStr);
  return onSnapshot(docRef, (snap) => {
    const data = snap.exists() ? snap.data() : {};
    const existing = (((data as any).progress as any[]) || []).map(firestoreToProgress);
    const progress = Object.values(TimeSlot).map(slot =>
      existing.find(p => p.timeSlot === slot) || createDefaultProgress(slot)
    );
    callback({ progress, date: today });
  });
}

// トレーニング完了を記録
export async function recordTrainingCompleted(
  userId: string,
  timeSlot: TimeSlot
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.trainingCompleted += 1;
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// マインドフルネス完了を記録
export async function recordMindfulnessCompleted(
  userId: string,
  timeSlot: TimeSlot
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.mindfulnessCompleted += 1;
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// ログ記録（食事）
export async function recordMealLog(
  userId: string,
  timeSlot: TimeSlot,
  calories: number = 0
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.logProgress.mealLogged = true;
    slotProgress.logProgress.mealKcalLogged =
      (slotProgress.logProgress.mealKcalLogged || 0) + Math.max(0, calories);
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// ログ記録（飲み物）
export async function recordDrinkLog(
  userId: string,
  timeSlot: TimeSlot,
  ml: number = 0
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.logProgress.drinkLogged = true;
    slotProgress.logProgress.drinkMlLogged =
      (slotProgress.logProgress.drinkMlLogged || 0) + Math.max(0, ml);
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

export async function recordStretchCompleted(
  userId: string,
  timeSlot: TimeSlot,
  minutes: number
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.stretchMinutesCompleted =
      (slotProgress.stretchMinutesCompleted || 0) + Math.max(0, minutes);
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

export async function toggleCustomActivity(
  userId: string,
  timeSlot: TimeSlot,
  activityId: string
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    const current = new Set(slotProgress.completedActivityIds || []);
    if (current.has(activityId)) {
      current.delete(activityId);
    } else {
      current.add(activityId);
    }
    slotProgress.completedActivityIds = Array.from(current);
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// ログ記録（マインド入力）
export async function recordMindInputLog(
  userId: string,
  timeSlot: TimeSlot
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.logProgress.mindInputLogged = true;
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// iOSがHealthKitから記録した1日全体の実績（睡眠スコア・PFCスコアなど）
export interface GlobalProgress {
  workoutMinutes: number;
  standHours: number;
  sleepHours: number;
  sleepScore: number;
  pfcScore: number;
  lastUpdated?: Date;
}

// 今日のglobalProgressを取得（iOSがHealthKitから書き込んだデータ）
export async function getGlobalProgress(userId: string): Promise<GlobalProgress | null> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dateStr = dateToString(today);

  const docRef = doc(db, 'users', userId, TIME_SLOT_PROGRESS_COLLECTION, dateStr);
  const docSnap = await getDoc(docRef);

  if (docSnap.exists()) {
    const data = docSnap.data();
    if (data.globalProgress) {
      const gp = data.globalProgress;
      return {
        workoutMinutes: gp.workoutMinutes || 0,
        standHours: gp.standHours || 0,
        sleepHours: gp.sleepHours || 0,
        sleepScore: gp.sleepScore || 0,
        pfcScore: gp.pfcScore || 0,
        lastUpdated: gp.lastUpdated ? (gp.lastUpdated as Timestamp).toDate() : undefined,
      };
    }
  }
  return null;
}
