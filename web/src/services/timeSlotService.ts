import {
  doc,
  getDoc,
  setDoc,
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

const TIME_SLOT_GOALS_COLLECTION = 'time-slot-goals';
const TIME_SLOT_PROGRESS_COLLECTION = 'time-slot-progress';

// 日付を YYYY-MM-DD 形式の文字列に変換
function dateToString(date: Date): string {
  return date.toISOString().split('T')[0];
}

// デフォルトの目標を作成
function createDefaultGoal(timeSlot: TimeSlot): TimeSlotGoal {
  return {
    timeSlot,
    trainingGoal: 1,
    mindfulnessGoal: 1,
    logGoal: {
      mealRequired: true,
      drinkRequired: true,
      mindInputRequired: false
    },
    reminderEnabled: false
  };
}

// デフォルトの実績を作成
function createDefaultProgress(timeSlot: TimeSlot): TimeSlotProgress {
  return {
    timeSlot,
    trainingCompleted: 0,
    mindfulnessCompleted: 0,
    logProgress: {
      mealLogged: false,
      drinkLogged: false,
      mindInputLogged: false
    },
    lastUpdated: new Date()
  };
}

// Firestore データから TimeSlotGoal に変換
function firestoreToGoal(data: any): TimeSlotGoal {
  return {
    timeSlot: data.timeSlot as TimeSlot,
    trainingGoal: data.trainingGoal || 1,
    mindfulnessGoal: data.mindfulnessGoal || 1,
    logGoal: data.logGoal || {
      mealRequired: true,
      drinkRequired: true,
      mindInputRequired: false
    },
    reminderEnabled: data.reminderEnabled || false,
    reminderTime: data.reminderTime
      ? (data.reminderTime as Timestamp).toDate()
      : undefined
  };
}

// TimeSlotGoal から Firestore データに変換
function goalToFirestore(goal: TimeSlotGoal): any {
  const data: any = {
    timeSlot: goal.timeSlot,
    trainingGoal: goal.trainingGoal,
    mindfulnessGoal: goal.mindfulnessGoal,
    logGoal: goal.logGoal,
    reminderEnabled: goal.reminderEnabled
  };

  if (goal.reminderTime) {
    data.reminderTime = Timestamp.fromDate(goal.reminderTime);
  }

  return data;
}

// Firestore データから TimeSlotProgress に変換
function firestoreToProgress(data: any): TimeSlotProgress {
  return {
    timeSlot: data.timeSlot as TimeSlot,
    trainingCompleted: data.trainingCompleted || 0,
    mindfulnessCompleted: data.mindfulnessCompleted || 0,
    logProgress: data.logProgress || {
      mealLogged: false,
      drinkLogged: false,
      mindInputLogged: false
    },
    lastUpdated: data.lastUpdated
      ? (data.lastUpdated as Timestamp).toDate()
      : new Date()
  };
}

// TimeSlotProgress から Firestore データに変換
function progressToFirestore(progress: TimeSlotProgress): any {
  return {
    timeSlot: progress.timeSlot,
    trainingCompleted: progress.trainingCompleted,
    mindfulnessCompleted: progress.mindfulnessCompleted,
    logProgress: progress.logProgress,
    lastUpdated: Timestamp.fromDate(progress.lastUpdated)
  };
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
    const goals = (data.goals || []).map(firestoreToGoal);
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

  await setDoc(docRef, data);
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
    const progress = (data.progress || []).map(firestoreToProgress);
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

  await setDoc(docRef, data);
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
  timeSlot: TimeSlot
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.logProgress.mealLogged = true;
    slotProgress.lastUpdated = new Date();
    await saveTodayProgress(userId, progress);
  }
}

// ログ記録（飲み物）
export async function recordDrinkLog(
  userId: string,
  timeSlot: TimeSlot
): Promise<void> {
  const progress = await getTodayProgress(userId);
  const slotProgress = progress.progress.find(p => p.timeSlot === timeSlot);

  if (slotProgress) {
    slotProgress.logProgress.drinkLogged = true;
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
        sleepScore: gp.sleepScore || 0,
        pfcScore: gp.pfcScore || 0,
        lastUpdated: gp.lastUpdated ? (gp.lastUpdated as Timestamp).toDate() : undefined,
      };
    }
  }
  return null;
}
