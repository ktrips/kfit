import React, { useEffect, useState } from 'react';
import { useAppStore } from '../store/appStore';
import {
  getDrinkDefaults,
  getMealDefaults,
  getTodayIntakeSummary,
  recordDrinkIntake,
  recordMealIntake,
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

  const load = async () => {
    if (!user) return;
    setLoading(true);
    try {
      setSummary(await getTodayIntakeSummary(user.uid));
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
        drinkCount: current.drinkCount + 1,
        logs: [newLog, ...current.logs],
      } : current);
    } finally {
      setSavingKey(null);
    }
  };

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

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

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <SummaryCard label="摂取" value={`${summary?.calories ?? 0}`} unit="kcal" color="#FF9600" />
          <SummaryCard label="水分" value={`${summary?.waterMl ?? 0}`} unit="ml" color="#1CB0F6" />
          <SummaryCard label="カフェイン" value={`${summary?.caffeineMg ?? 0}`} unit="mg" color="#CE82FF" />
          <SummaryCard label="アルコール" value={`${Math.round(summary?.alcoholGrams ?? 0)}`} unit="g" color="#FF4B4B" />
        </div>

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
                  <p className="font-black text-duo-green text-sm">
                    {log.type === 'meal' ? `${log.calories} kcal` : `${log.waterMl || log.alcoholGrams} ${log.waterMl ? 'ml' : 'g'}`}
                  </p>
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
