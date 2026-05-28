import React, { useEffect, useState } from 'react';
import { useAppStore } from '../store/appStore';
import {
  getDietGoalSettings,
  getDrinkDefaults,
  getMealDefaults,
  getTodayIntakeSummary,
  recordDrinkIntake,
  recordMealIntake,
  saveDietGoalSettings,
} from '../services/wellnessService';
import { getCurrentTimeSlot } from '../types/timeSlot';
import { recordDrinkLog, recordMealLog } from '../services/timeSlotService';
import type { DrinkType, IntakeSummary, MealType } from '../types/wellness';

const MEALS: { id: MealType; emoji: string }[] = [
  { id: 'breakfast', emoji: '🌅' },
  { id: 'lunch', emoji: '☀️' },
  { id: 'dinner', emoji: '🌙' },
  { id: 'snack', emoji: '🍪' },
];

const DRINKS: { id: DrinkType; emoji: string; amountLabel: string }[] = [
  { id: 'water', emoji: '💧', amountLabel: '250ml' },
  { id: 'coffee', emoji: '☕', amountLabel: '180ml' },
  { id: 'alcohol', emoji: '🍺', amountLabel: '20g' },
];

export const IntakeView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [summary, setSummary] = useState<IntakeSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [calorieGoal, setCalorieGoal] = useState(2000);
  const [editingGoal, setEditingGoal] = useState(false);
  const [goalInputValue, setGoalInputValue] = useState('');
  const [savingGoal, setSavingGoal] = useState(false);

  const load = async () => {
    if (!user) return;
    setLoading(true);
    try {
      const [summaryData, dietSettings] = await Promise.all([
        getTodayIntakeSummary(user.uid),
        getDietGoalSettings(user.uid),
      ]);
      setSummary(summaryData);
      setCalorieGoal(dietSettings.dailyIntakeKcalGoal);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, [user]);

  const handleMeal = async (mealType: MealType) => {
    if (!user) return;
    const defaults = getMealDefaults(mealType);
    const slot = getCurrentTimeSlot();
    setSavingKey(mealType);
    try {
      const newLog = await recordMealIntake(user.uid, mealType, defaults.calories, slot);
      await recordMealLog(user.uid, slot, defaults.calories);
      setSummary(current => current ? {
        ...current,
        calories: current.calories + newLog.calories,
        protein: current.protein + newLog.protein,
        fat: current.fat + newLog.fat,
        carbs: current.carbs + newLog.carbs,
        mealCount: current.mealCount + 1,
        logs: [newLog, ...current.logs],
      } : current);
    } finally {
      setSavingKey(null);
    }
  };

  const handleDrink = async (drinkType: DrinkType) => {
    if (!user) return;
    const defaults = getDrinkDefaults(drinkType);
    const slot = getCurrentTimeSlot();
    setSavingKey(drinkType);
    try {
      const newLog = await recordDrinkIntake(user.uid, drinkType, defaults.waterMl || undefined, slot);
      await recordDrinkLog(user.uid, slot, defaults.waterMl);
      setSummary(current => current ? {
        ...current,
        calories: current.calories + newLog.calories,
        waterMl: current.waterMl + newLog.waterMl,
        caffeineMg: current.caffeineMg + newLog.caffeineMg,
        alcoholGrams: current.alcoholGrams + newLog.alcoholGrams,
        carbs: current.carbs + newLog.carbs,
        drinkCount: current.drinkCount + 1,
        logs: [newLog, ...current.logs],
      } : current);
    } finally {
      setSavingKey(null);
    }
  };

  const startEditGoal = () => {
    setGoalInputValue(String(calorieGoal));
    setEditingGoal(true);
  };

  const saveGoal = async () => {
    if (!user) return;
    const newGoal = parseInt(goalInputValue, 10);
    if (isNaN(newGoal) || newGoal <= 0) return;
    setSavingGoal(true);
    try {
      const currentSettings = await getDietGoalSettings(user.uid);
      await saveDietGoalSettings(user.uid, { ...currentSettings, dailyIntakeKcalGoal: newGoal });
      setCalorieGoal(newGoal);
      setEditingGoal(false);
    } finally {
      setSavingGoal(false);
    }
  };

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

  const consumed = summary?.calories ?? 0;
  const calorieProgress = Math.min(consumed / calorieGoal, 1);
  const protein = summary?.protein ?? 0;
  const fat = summary?.fat ?? 0;
  const carbs = summary?.carbs ?? 0;
  const totalPFC = protein + fat + carbs;

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">
        <div className="duo-card p-5">
          <p className="text-duo-gray font-bold text-xs uppercase tracking-wider">Food & Drink</p>
          <h1 className="text-2xl font-black text-duo-dark">食事・ドリンク記録</h1>
          <p className="text-sm font-bold text-duo-gray mt-1">
            Webでは簡易入力でFirestoreへ保存し、時間帯別目標にも反映します。
          </p>
        </div>

        {/* Calorie Goal Progress */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-black text-duo-dark">カロリー目標</h2>
            {!editingGoal ? (
              <button onClick={startEditGoal} className="text-sm font-bold text-duo-blue underline">
                目標を変更
              </button>
            ) : (
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  value={goalInputValue}
                  onChange={e => setGoalInputValue(e.target.value)}
                  className="w-20 rounded-lg border-2 border-duo-gray-mid px-2 py-1 font-bold text-sm text-duo-dark text-right"
                />
                <span className="text-sm text-duo-gray font-bold">kcal</span>
                <button
                  onClick={saveGoal}
                  disabled={savingGoal}
                  className="text-sm font-black text-duo-green"
                >
                  {savingGoal ? '...' : '保存'}
                </button>
                <button onClick={() => setEditingGoal(false)} className="text-sm font-bold text-duo-gray">
                  ✕
                </button>
              </div>
            )}
          </div>
          <div className="flex items-end gap-2 mb-2">
            <span className="text-3xl font-black" style={{ color: calorieProgress >= 1 ? '#FF4B4B' : '#FF9600' }}>
              {consumed}
            </span>
            <span className="text-sm font-bold text-duo-gray mb-1">/ {calorieGoal} kcal</span>
            <span
              className="text-sm font-bold ml-auto mb-1"
              style={{ color: calorieProgress >= 1 ? '#FF4B4B' : '#58CC02' }}
            >
              {Math.round(calorieProgress * 100)}%
            </span>
          </div>
          <div className="w-full bg-gray-100 rounded-full h-3">
            <div
              className="h-3 rounded-full transition-all duration-500"
              style={{
                width: `${Math.min(calorieProgress * 100, 100)}%`,
                backgroundColor: calorieProgress >= 1 ? '#FF4B4B' : '#FF9600',
              }}
            />
          </div>
          <p className="text-xs font-bold text-duo-gray mt-1">
            残り {Math.max(calorieGoal - consumed, 0)} kcal
          </p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <SummaryCard label="摂取" value={`${summary?.calories ?? 0}`} unit="kcal" color="#FF9600" />
          <SummaryCard label="水分" value={`${summary?.waterMl ?? 0}`} unit="ml" color="#1CB0F6" />
          <SummaryCard label="カフェイン" value={`${summary?.caffeineMg ?? 0}`} unit="mg" color="#CE82FF" />
          <SummaryCard label="アルコール" value={`${Math.round(summary?.alcoholGrams ?? 0)}`} unit="g" color="#FF4B4B" />
        </div>

        {/* PFC Balance */}
        {totalPFC > 0 && (
          <div className="duo-card p-5">
            <h2 className="text-lg font-black text-duo-dark mb-3">PFCバランス</h2>
            <div className="grid grid-cols-3 gap-3 mb-3">
              <MacroCard label="タンパク質" value={protein} unit="g" color="#1CB0F6" />
              <MacroCard label="脂質" value={fat} unit="g" color="#FF9600" />
              <MacroCard label="炭水化物" value={carbs} unit="g" color="#58CC02" />
            </div>
            <div className="flex rounded-full overflow-hidden h-4">
              <div
                className="transition-all duration-500"
                style={{ width: `${(protein / totalPFC) * 100}%`, backgroundColor: '#1CB0F6' }}
                title={`P: ${protein}g`}
              />
              <div
                className="transition-all duration-500"
                style={{ width: `${(fat / totalPFC) * 100}%`, backgroundColor: '#FF9600' }}
                title={`F: ${fat}g`}
              />
              <div
                className="transition-all duration-500"
                style={{ width: `${(carbs / totalPFC) * 100}%`, backgroundColor: '#58CC02' }}
                title={`C: ${carbs}g`}
              />
            </div>
            <div className="flex justify-between mt-1">
              <span className="text-xs font-bold" style={{ color: '#1CB0F6' }}>
                P {Math.round((protein / totalPFC) * 100)}%
              </span>
              <span className="text-xs font-bold" style={{ color: '#FF9600' }}>
                F {Math.round((fat / totalPFC) * 100)}%
              </span>
              <span className="text-xs font-bold" style={{ color: '#58CC02' }}>
                C {Math.round((carbs / totalPFC) * 100)}%
              </span>
            </div>
          </div>
        )}

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">食事</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {MEALS.map(item => {
              const defaults = getMealDefaults(item.id);
              return (
                <button
                  key={item.id}
                  onClick={() => handleMeal(item.id)}
                  disabled={savingKey === item.id}
                  className="duo-exercise-btn bg-white text-left"
                >
                  <div className="text-3xl mb-2">{item.emoji}</div>
                  <div className="font-black text-duo-dark">{defaults.label}</div>
                  <div className="text-sm font-bold text-duo-gray">{defaults.calories} kcal</div>
                  <div className="text-xs text-duo-gray mt-1">
                    P:{defaults.protein}g F:{defaults.fat}g C:{defaults.carbs}g
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">ドリンク</h2>
          <div className="grid grid-cols-3 gap-3">
            {DRINKS.map(item => {
              const defaults = getDrinkDefaults(item.id);
              return (
                <button
                  key={item.id}
                  onClick={() => handleDrink(item.id)}
                  disabled={savingKey === item.id}
                  className="duo-exercise-btn bg-white text-left"
                >
                  <div className="text-3xl mb-2">{item.emoji}</div>
                  <div className="font-black text-duo-dark">{defaults.label}</div>
                  <div className="text-sm font-bold text-duo-gray">{item.amountLabel}</div>
                </button>
              );
            })}
          </div>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">今日のログ</h2>
          {(summary?.logs.length ?? 0) === 0 ? (
            <p className="text-sm font-bold text-duo-gray">まだ記録がありません。</p>
          ) : (
            <div className="space-y-2">
              {summary?.logs.map(log => (
                <div key={log.id} className="flex items-center justify-between rounded-xl bg-duo-gray-light px-3 py-2">
                  <div>
                    <p className="font-black text-duo-dark text-sm">{log.label}</p>
                    <p className="text-xs font-bold text-duo-gray">
                      {log.timestamp.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="font-black text-duo-green text-sm">
                      {log.type === 'meal'
                        ? `${log.calories} kcal`
                        : `${log.waterMl || log.alcoholGrams} ${log.waterMl ? 'ml' : 'g'}`}
                    </p>
                    {log.type === 'meal' && log.protein > 0 && (
                      <p className="text-xs text-duo-gray">P:{log.protein} F:{log.fat} C:{log.carbs}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

const SummaryCard: React.FC<{ label: string; value: string; unit: string; color: string }> = ({ label, value, unit, color }) => (
  <div className="duo-card p-4">
    <p className="text-xs font-bold text-duo-gray">{label}</p>
    <p className="text-2xl font-black" style={{ color }}>{value}</p>
    <p className="text-xs font-bold text-duo-gray">{unit}</p>
  </div>
);

const MacroCard: React.FC<{ label: string; value: number; unit: string; color: string }> = ({ label, value, unit, color }) => (
  <div className="rounded-2xl p-3 text-center" style={{ background: `${color}15` }}>
    <p className="text-xs font-bold text-duo-gray">{label}</p>
    <p className="text-xl font-black" style={{ color }}>{value}</p>
    <p className="text-xs font-bold text-duo-gray">{unit}</p>
  </div>
);
