// 時間帯の定義
export enum TimeSlot {
  MIDNIGHT = 'midnight',   // 0:00 - 6:00
  MORNING = 'morning',     // 6:00 - 10:00
  NOON = 'noon',          // 10:00 - 14:00
  AFTERNOON = 'afternoon', // 14:00 - 18:00
  EVENING = 'evening'      // 18:00 - 24:00
}

export interface TimeSlotInfo {
  slot: TimeSlot;
  displayName: string;
  emoji: string;
  timeRange: string;
  startHour: number;
  endHour: number;
}

export const TIME_SLOT_INFO: Record<TimeSlot, TimeSlotInfo> = {
  [TimeSlot.MIDNIGHT]: {
    slot: TimeSlot.MIDNIGHT,
    displayName: '夜中',
    emoji: '🌙',
    timeRange: '0:00 - 6:00',
    startHour: 0,
    endHour: 6
  },
  [TimeSlot.MORNING]: {
    slot: TimeSlot.MORNING,
    displayName: '朝',
    emoji: '🌅',
    timeRange: '6:00 - 10:00',
    startHour: 6,
    endHour: 10
  },
  [TimeSlot.NOON]: {
    slot: TimeSlot.NOON,
    displayName: '昼',
    emoji: '☀️',
    timeRange: '10:00 - 14:00',
    startHour: 10,
    endHour: 14
  },
  [TimeSlot.AFTERNOON]: {
    slot: TimeSlot.AFTERNOON,
    displayName: '午後',
    emoji: '🌤️',
    timeRange: '14:00 - 18:00',
    startHour: 14,
    endHour: 18
  },
  [TimeSlot.EVENING]: {
    slot: TimeSlot.EVENING,
    displayName: '夜',
    emoji: '🌙',
    timeRange: '18:00 - 24:00',
    startHour: 18,
    endHour: 24
  }
};

// 現在の時刻から時間帯を取得
export function getCurrentTimeSlot(): TimeSlot {
  const hour = new Date().getHours();
  if (hour < 6) return TimeSlot.MIDNIGHT;
  if (hour >= 6 && hour < 10) return TimeSlot.MORNING;
  if (hour >= 10 && hour < 14) return TimeSlot.NOON;
  if (hour >= 14 && hour < 18) return TimeSlot.AFTERNOON;
  return TimeSlot.EVENING;
}

// ログ目標
export interface LogGoal {
  mealRequired: boolean;
  drinkRequired: boolean;
  mindInputRequired: boolean;
  mealKcalGoal?: number;
  drinkMlGoal?: number;
}

export interface CustomActivity {
  id: string;
  title: string;
  emoji: string;
  targetCount: number;
}

// 時間帯ごとの目標
export interface TimeSlotGoal {
  timeSlot: TimeSlot;
  trainingGoal: number;           // トレーニングセット数
  mindfulnessGoal: number;        // マインドフルネス回数
  stretchMinutesGoal?: number;    // Reflect/ストレッチ分数
  logGoal: LogGoal;               // ログ目標
  customActivities?: CustomActivity[];
  reminderEnabled: boolean;       // リマインダー有効
  reminderTime?: Date;            // リマインダー時刻
}

// ログ進捗
export interface LogProgress {
  mealLogged: boolean;
  drinkLogged: boolean;
  mindInputLogged: boolean;
  mealKcalLogged?: number;
  drinkMlLogged?: number;
}

// 時間帯ごとの実績
export interface TimeSlotProgress {
  timeSlot: TimeSlot;
  trainingCompleted: number;      // 完了したトレーニングセット数
  mindfulnessCompleted: number;   // 完了したマインドフルネス回数
  stretchMinutesCompleted?: number;
  logProgress: LogProgress;
  completedActivityIds?: string[];
  lastUpdated: Date;
}

// 1日の時間帯別目標設定
export interface DailyTimeSlotSettings {
  goals: TimeSlotGoal[];
  date: Date;
}

// 1日の時間帯別実績
export interface DailyTimeSlotProgress {
  progress: TimeSlotProgress[];
  date: Date;
}

// 目標達成率を計算
export function calculateCompletionRate(
  progress: TimeSlotProgress,
  goal: TimeSlotGoal
): number {
  let totalGoals = 0;
  let completed = 0;

  // トレーニング
  if (goal.trainingGoal > 0) {
    totalGoals += 1;
    if (progress.trainingCompleted >= goal.trainingGoal) {
      completed += 1;
    }
  }

  // マインドフルネス
  if (goal.mindfulnessGoal > 0) {
    totalGoals += 1;
    if (progress.mindfulnessCompleted >= goal.mindfulnessGoal) {
      completed += 1;
    }
  }

  if ((goal.stretchMinutesGoal ?? 0) > 0) {
    totalGoals += 1;
    if ((progress.stretchMinutesCompleted ?? 0) >= (goal.stretchMinutesGoal ?? 0)) {
      completed += 1;
    }
  }

  // ログ
  const logGoalsCount =
    (goal.logGoal.mealRequired ? 1 : 0) +
    (goal.logGoal.drinkRequired ? 1 : 0) +
    (goal.logGoal.mindInputRequired ? 1 : 0);

  if (logGoalsCount > 0) {
    totalGoals += 1;
    let logCompletedCount = 0;

    if (goal.logGoal.mindInputRequired && progress.logProgress.mindInputLogged) {
      logCompletedCount += 1;
    }

    if (goal.logGoal.mealRequired) {
      const mealGoal = goal.logGoal.mealKcalGoal ?? 0;
      logCompletedCount += mealGoal > 0
        ? ((progress.logProgress.mealKcalLogged ?? 0) >= mealGoal ? 1 : 0)
        : (progress.logProgress.mealLogged ? 1 : 0);
    }

    if (goal.logGoal.drinkRequired) {
      const drinkGoal = goal.logGoal.drinkMlGoal ?? 0;
      logCompletedCount += drinkGoal > 0
        ? ((progress.logProgress.drinkMlLogged ?? 0) >= drinkGoal ? 1 : 0)
        : (progress.logProgress.drinkLogged ? 1 : 0);
    }

    if (logCompletedCount >= logGoalsCount) {
      completed += 1;
    }
  }

  const customActivities = goal.customActivities ?? [];
  if (customActivities.length > 0) {
    customActivities.forEach(activity => {
      totalGoals += 1;
      if ((progress.completedActivityIds ?? []).includes(activity.id)) {
        completed += 1;
      }
    });
  }

  return totalGoals > 0 ? completed / totalGoals : 0;
}

// 完全達成したか
export function isFullyCompleted(
  progress: TimeSlotProgress,
  goal: TimeSlotGoal
): boolean {
  return calculateCompletionRate(progress, goal) >= 1.0;
}
