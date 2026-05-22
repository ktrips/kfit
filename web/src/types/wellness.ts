export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack';
export type DrinkType = 'water' | 'coffee' | 'alcohol';

export interface IntakeLog {
  id: string;
  type: 'meal' | 'drink';
  label: string;
  calories: number;
  waterMl: number;
  caffeineMg: number;
  alcoholGrams: number;
  timeSlot: string;
  timestamp: Date;
}

export interface IntakeSummary {
  calories: number;
  waterMl: number;
  caffeineMg: number;
  alcoholGrams: number;
  mealCount: number;
  drinkCount: number;
  logs: IntakeLog[];
}

export interface DietGoalSettings {
  startDate: string;
  goalDate: string;
  startWeightKg: number;
  startBodyFatPercent: number;
  currentWeightKg: number;
  currentBodyFatPercent: number;
  goalWeightKg: number;
  goalBodyFatPercent: number;
  dailyIntakeKcalGoal: number;
  dailyBurnKcalGoal: number;
}

export interface MindMetrics {
  latestHeartRate: number;
  latestHRV: number;
  averageHeartRate: number;
  averageHRV: number;
  mindfulnessMinutes: number;
  standHours: number;
  steps: number;
  updatedAt?: Date;
}
