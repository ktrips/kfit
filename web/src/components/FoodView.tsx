import React, { useEffect, useState } from 'react';
import { useAppStore } from '../store/appStore';
import {
  getDrinkDefaults,
  getMealDefaults,
  getDietGoalSettings,
  getTodayIntakeSummary,
  recordDrinkIntake,
  recordMealIntake,
} from '../services/wellnessService';
import { getCurrentTimeSlot } from '../types/timeSlot';
import { recordDrinkLog, recordMealLog } from '../services/timeSlotService';
import type { DietGoalSettings, DrinkType, IntakeSummary, MealType } from '../types/wellness';

const WATER_GOAL_ML = 2000;
const CAFFEINE_LIMIT_MG = 400;
const ALCOHOL_LIMIT_G = 20;

const MEALS: { id: MealType; emoji: string; label: string }[] = [
  { id: 'breakfast', emoji: '🌅', label: '朝食' },
  { id: 'lunch',     emoji: '🍱', label: '昼食' },
  { id: 'dinner',    emoji: '🌙', label: '夕食' },
  { id: 'snack',     emoji: '🍪', label: '間食' },
];

const DRINKS: { id: DrinkType; emoji: string; label: string; amount: string }[] = [
  { id: 'water',   emoji: '💧', label: '水',        amount: '250ml' },
  { id: 'coffee',  emoji: '☕', label: 'コーヒー', amount: '180ml' },
  { id: 'alcohol', emoji: '🍺', label: 'アルコール', amount: '20g' },
];

function buildAdvice(
  waterMl: number,
  caffeineMg: number,
  alcoholG: number,
  calories: number,
  intakeGoal: number,
): { emoji: string; title: string; message: string; color: string }[] {
  const tips: { emoji: string; title: string; message: string; color: string }[] = [];
  const waterPct = WATER_GOAL_ML > 0 ? (waterMl / WATER_GOAL_ML) * 100 : 0;
  if (waterPct >= 100) {
    tips.push({ emoji: '💧', title: '水分目標達成！', message: '今日の水分摂取目標をクリア。このペースを維持しましょう！', color: '#58CC02' });
  } else if (waterPct < 60) {
    tips.push({ emoji: '💧', title: '水分補給を忘れずに', message: `あと${Math.ceil(WATER_GOAL_ML - waterMl)}mlで目標です。こまめに水やお茶を飲みましょう。`, color: '#1CB0F6' });
  }
  if (caffeineMg >= CAFFEINE_LIMIT_MG * 0.7) {
    tips.push({ emoji: '☕', title: 'カフェイン注意', message: `1日の目安（${CAFFEINE_LIMIT_MG}mg）に近づいています。午後はカフェインを控えめに。`, color: '#FF9600' });
  }
  if (alcoholG >= ALCOHOL_LIMIT_G) {
    tips.push({ emoji: '🍺', title: 'アルコール上限', message: '適量を超えています。水を多めに飲んで体を労わりましょう。', color: '#FF4B4B' });
  }
  if (intakeGoal > 0 && calories >= intakeGoal * 0.9) {
    tips.push({ emoji: '🍽️', title: '摂取カロリーが目標に近い', message: '今日の目標カロリーに近づいています。間食を控えめにしましょう。', color: '#CE82FF' });
  }
  if (tips.length === 0) {
    tips.push({ emoji: '✨', title: '順調です！', message: '水分・カロリーともにバランスよく記録されています。この調子で続けましょう！', color: '#58CC02' });
  }
  return tips;
}

interface IntakeItemProps {
  icon: string;
  iconColor: string;
  label: string;
  value: number;
  goal: number;
  unit: string;
  formatVal: (v: number) => string;
  isReverse: boolean;
}

const IntakeItem: React.FC<IntakeItemProps> = ({ icon, iconColor, label, value, goal, unit, formatVal, isReverse }) => {
  const pct = goal > 0 ? Math.min(100, Math.round((value / goal) * 100)) : 0;
  const isOver = goal > 0 && value > goal;
  let barColor = iconColor;
  if (isReverse) {
    barColor = isOver ? '#FF4B4B' : pct >= 70 ? '#FF9600' : '#58CC02';
  } else {
    barColor = pct >= 100 ? '#58CC02' : pct >= 70 ? '#58CC02' : pct >= 40 ? '#FF9600' : iconColor;
  }

  let advice = '';
  if (label === '水分') {
    if (value <= 0) advice = '記録なし';
    else if (pct >= 100) advice = '目標達成！';
    else advice = `あと${Math.ceil(goal - value)}ml`;
  } else if (label === 'カフェイン') {
    if (value <= 0) advice = '摂取なし';
    else if (pct >= 100) advice = '上限超過！';
    else if (pct >= 70) advice = '上限に近い';
    else advice = '安全な範囲';
  } else {
    if (value <= 0) advice = '飲酒なし';
    else if (pct >= 100) advice = '上限超過！';
    else if (pct >= 70) advice = '飲み過ぎ注意';
    else advice = '適量範囲内';
  }

  return (
    <div className="flex-1 flex flex-col items-center gap-1 rounded-2xl py-3 px-2" style={{ background: `${iconColor}14` }}>
      <span style={{ fontSize: 18 }}>{icon}</span>
      <p className="text-[9px] font-black text-duo-dark">{label}</p>
      <p className="text-sm font-black leading-none" style={{ color: isOver && isReverse ? '#FF4B4B' : barColor }}>
        {value > 0 ? formatVal(value) : '—'}
      </p>
      <p className="text-[8px] font-bold text-duo-gray">{unit}</p>
      {goal > 0 && (
        <div className="w-full bg-gray-200 rounded-full" style={{ height: 3 }}>
          <div className="rounded-full transition-all" style={{ height: 3, width: `${pct}%`, background: barColor }} />
        </div>
      )}
      {goal > 0 && <p className="text-[8px] font-bold" style={{ color: barColor }}>{pct}%</p>}
      <p className="text-[8px] font-bold leading-none" style={{ color: barColor }}>{advice}</p>
    </div>
  );
};

export const FoodView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [summary, setSummary] = useState<IntakeSummary | null>(null);
  const [dietGoal, setDietGoal] = useState<DietGoalSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<{ key: string; msg: string; action: () => void } | null>(null);

  const load = async () => {
    if (!user) return;
    setLoading(true);
    try {
      const [s, d] = await Promise.all([
        getTodayIntakeSummary(user.uid),
        getDietGoalSettings(user.uid),
      ]);
      setSummary(s);
      setDietGoal(d);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [user]);

  const handleMeal = (mealType: MealType) => {
    const defaults = getMealDefaults(mealType);
    setConfirming({
      key: mealType,
      msg: `${defaults.label} ${defaults.calories}kcal を記録しますか？`,
      action: async () => {
        if (!user) return;
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
      },
    });
  };

  const handleDrink = (drinkType: DrinkType) => {
    const defaults = getDrinkDefaults(drinkType);
    const amountLabel = drinkType === 'alcohol' ? `${defaults.alcoholGrams}g` : `${defaults.waterMl}ml`;
    setConfirming({
      key: drinkType,
      msg: `${defaults.label} ${amountLabel} を記録しますか？`,
      action: async () => {
        if (!user) return;
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
      },
    });
  };

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

  const calories = summary?.calories ?? 0;
  const waterMl = summary?.waterMl ?? 0;
  const caffeineMg = summary?.caffeineMg ?? 0;
  const alcoholG = summary?.alcoholGrams ?? 0;
  const mealCount = summary?.mealCount ?? 0;
  const intakeGoal = dietGoal?.dailyIntakeKcalGoal ?? 0;
  const caloriePct = intakeGoal > 0 ? Math.min(100, Math.round((calories / intakeGoal) * 100)) : 0;
  const tips = buildAdvice(waterMl, caffeineMg, alcoholG, calories, intakeGoal);

  return (
    <div className="min-h-screen pb-10" style={{ background: '#F7F7F7' }}>
      {/* Header */}
      <div
        className="sticky top-0 z-10 flex items-center justify-between px-4 py-3"
        style={{ background: 'linear-gradient(135deg, #FF7200 0%, #D93600 100%)' }}
      >
        <div className="flex items-center gap-2">
          <span className="text-white text-base">🍴</span>
          <span className="font-black text-base leading-none">
            <span style={{ color: '#FFF3C0' }}>Food</span>
            <span className="text-white">ingo</span>
          </span>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1 px-2 py-1 rounded-lg" style={{ background: 'rgba(255,255,255,0.18)' }}>
            <span className="text-[10px]" style={{ color: '#FFF3C0' }}>🔥</span>
            <span className="text-white font-black text-xs">{calories}</span>
            <span className="text-[9px] font-bold" style={{ color: 'rgba(255,255,255,0.8)' }}>kcal</span>
          </div>
          {mealCount > 0 && (
            <div className="flex items-center gap-1 px-2 py-1 rounded-lg" style={{ background: 'rgba(255,255,255,0.18)' }}>
              <span className="text-white font-black text-xs">{mealCount}食</span>
            </div>
          )}
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 pt-4 space-y-3">

        {/* カロリーサマリーカード */}
        <div className="bg-white rounded-2xl p-4 shadow-sm" style={{ border: '1.5px solid #f0f0f0' }}>
          <div className="flex items-center justify-between mb-2">
            <p className="font-black text-duo-dark text-sm">🔥 今日の摂取カロリー</p>
            {intakeGoal > 0 && (
              <p className="text-xs font-bold text-duo-gray">目標 {intakeGoal} kcal</p>
            )}
          </div>
          <div className="flex items-end gap-2 mb-2">
            <span className="font-black leading-none" style={{ fontSize: 36, color: calories > 0 ? '#FF7200' : '#AFAFAF' }}>
              {calories}
            </span>
            <span className="font-bold text-duo-gray text-sm mb-1">kcal</span>
            {intakeGoal > 0 && (
              <span className="ml-auto font-black text-sm" style={{ color: caloriePct >= 90 ? '#FF4B4B' : '#FF9600' }}>
                {caloriePct}%
              </span>
            )}
          </div>
          {intakeGoal > 0 && (
            <div className="rounded-full bg-gray-100" style={{ height: 6 }}>
              <div
                className="rounded-full transition-all duration-500"
                style={{
                  height: 6,
                  width: `${caloriePct}%`,
                  background: caloriePct >= 100 ? '#FF4B4B' : caloriePct >= 80 ? '#FF9600' : '#FF7200',
                }}
              />
            </div>
          )}
          {calories === 0 && (
            <p className="text-duo-gray font-bold text-xs mt-2">食事を記録するとここに表示されます</p>
          )}
        </div>

        {/* 水分・カフェイン・アルコール */}
        <div className="bg-white rounded-2xl p-4 shadow-sm" style={{ border: '1.5px solid #f0f0f0' }}>
          <p className="font-black text-duo-dark text-sm mb-3">💧 水分・カフェイン・アルコール</p>
          <div className="flex gap-2">
            <IntakeItem
              icon="💧" iconColor="#1CB0F6" label="水分"
              value={waterMl} goal={WATER_GOAL_ML} unit="ml"
              formatVal={v => `${Math.round(v)}`} isReverse={false}
            />
            <IntakeItem
              icon="☕" iconColor="#8B5E3C" label="カフェイン"
              value={caffeineMg} goal={CAFFEINE_LIMIT_MG} unit="mg"
              formatVal={v => `${Math.round(v)}`} isReverse={true}
            />
            <IntakeItem
              icon="🍺" iconColor="#CE82FF" label="アルコール"
              value={alcoholG} goal={ALCOHOL_LIMIT_G} unit="g"
              formatVal={v => v.toFixed(1)} isReverse={true}
            />
          </div>
        </div>

        {/* アドバイス */}
        <div className="bg-white rounded-2xl p-4 shadow-sm" style={{ border: '1.5px solid #f0f0f0' }}>
          <div className="flex items-center gap-2 mb-3">
            <span className="text-sm">💡</span>
            <p className="font-black text-duo-dark text-sm">今日の食事アドバイス</p>
          </div>
          <div className="space-y-3">
            {tips.map((tip, i) => (
              <div key={i} className="flex items-start gap-3">
                <div
                  className="w-8 h-8 rounded-full flex items-center justify-center shrink-0"
                  style={{ background: `${tip.color}22` }}
                >
                  <span style={{ fontSize: 14 }}>{tip.emoji}</span>
                </div>
                <div>
                  <p className="font-black text-xs" style={{ color: tip.color }}>{tip.title}</p>
                  <p className="text-xs font-bold text-duo-dark leading-snug mt-0.5">{tip.message}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* クイックログ — 食事 */}
        <div className="bg-white rounded-2xl p-4 shadow-sm" style={{ border: '1.5px solid #f0f0f0' }}>
          <div className="flex items-center gap-2 mb-3">
            <span className="text-sm" style={{ color: '#FF7200' }}>⚡</span>
            <p className="font-black text-duo-dark text-sm">クイックログ</p>
          </div>
          <p className="text-xs font-bold text-duo-gray mb-2">食事</p>
          <div className="grid grid-cols-4 gap-2 mb-4">
            {MEALS.map(m => {
              const defaults = getMealDefaults(m.id);
              return (
                <button
                  key={m.id}
                  onClick={() => handleMeal(m.id)}
                  disabled={savingKey === m.id}
                  className="flex flex-col items-center gap-1 py-3 rounded-xl transition-all active:scale-95"
                  style={{
                    background: '#FFF3E0',
                    border: '2px solid #FF9600',
                    boxShadow: '0 2px 0 #CC7000',
                    opacity: savingKey === m.id ? 0.5 : 1,
                  }}
                >
                  <span style={{ fontSize: 20 }}>{m.emoji}</span>
                  <p className="font-black text-duo-dark text-[10px]">{m.label}</p>
                  <p className="font-bold text-duo-gray text-[9px]">{defaults.calories}kcal</p>
                </button>
              );
            })}
          </div>
          <p className="text-xs font-bold text-duo-gray mb-2">ドリンク</p>
          <div className="grid grid-cols-3 gap-2">
            {DRINKS.map(d => (
              <button
                key={d.id}
                onClick={() => handleDrink(d.id)}
                disabled={savingKey === d.id}
                className="flex flex-col items-center gap-1 py-3 rounded-xl transition-all active:scale-95"
                style={{
                  background: '#E3F2FD',
                  border: '2px solid #1CB0F6',
                  boxShadow: '0 2px 0 #0080C0',
                  opacity: savingKey === d.id ? 0.5 : 1,
                }}
              >
                <span style={{ fontSize: 20 }}>{d.emoji}</span>
                <p className="font-black text-duo-dark text-[10px]">{d.label}</p>
                <p className="font-bold text-duo-gray text-[9px]">{d.amount}</p>
              </button>
            ))}
          </div>
        </div>

        {/* 今日のログ */}
        {(summary?.logs.length ?? 0) > 0 && (
          <div className="bg-white rounded-2xl p-4 shadow-sm" style={{ border: '1.5px solid #f0f0f0' }}>
            <p className="font-black text-duo-dark text-sm mb-3">📋 今日のログ</p>
            <div className="space-y-2">
              {summary?.logs.map(log => (
                <div key={log.id} className="flex items-center justify-between rounded-xl px-3 py-2" style={{ background: '#F7F7F7' }}>
                  <div>
                    <p className="font-black text-duo-dark text-sm">{log.label}</p>
                    <p className="text-xs font-bold text-duo-gray">
                      {log.timestamp.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}
                    </p>
                  </div>
                  <p className="font-black text-sm" style={{ color: log.type === 'meal' ? '#FF7200' : '#1CB0F6' }}>
                    {log.type === 'meal'
                      ? `${log.calories} kcal`
                      : log.waterMl > 0
                        ? `${log.waterMl} ml`
                        : log.alcoholGrams > 0
                          ? `${log.alcoholGrams} g`
                          : `${log.caffeineMg} mg`}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

      </div>

      {/* 確認ダイアログ */}
      {confirming && (
        <div className="fixed inset-0 z-50 flex items-end justify-center" style={{ background: 'rgba(0,0,0,0.4)' }}>
          <div className="w-full max-w-md bg-white rounded-t-3xl p-6 space-y-4">
            <p className="font-black text-duo-dark text-base text-center">{confirming.msg}</p>
            <div className="flex gap-3">
              <button
                onClick={() => setConfirming(null)}
                className="flex-1 py-3 rounded-2xl font-black text-duo-gray"
                style={{ background: '#F0F0F0', border: '2px solid #e5e5e5' }}
              >
                キャンセル
              </button>
              <button
                onClick={() => {
                  confirming.action();
                  setConfirming(null);
                }}
                className="flex-1 py-3 rounded-2xl font-black text-white"
                style={{ background: '#FF7200', border: '2px solid #CC5800', boxShadow: '0 3px 0 #CC5800' }}
              >
                記録する
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
