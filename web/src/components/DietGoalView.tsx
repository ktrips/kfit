import React, { useEffect, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { getDietGoalSettings, saveDietGoalSettings, subscribeToTodayIntakeSummary } from '../services/wellnessService';
import type { DietGoalSettings, IntakeSummary } from '../types/wellness';
import { localDateKey } from '../utils/date';

function formatKg(value: number): string {
  return `${value.toFixed(1).replace('.0', '')}kg`;
}

function formatPercent(value: number): string {
  return `${Math.round(value)}%`;
}

function daysBetween(start: string, end: string): number {
  const s = new Date(start).getTime();
  const e = new Date(end).getTime();
  if (Number.isNaN(s) || Number.isNaN(e)) return 0;
  return Math.max(0, Math.ceil((e - s) / 86400000));
}

export const DietGoalView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [settings, setSettings] = useState<DietGoalSettings | null>(null);
  const [intake, setIntake] = useState<IntakeSummary | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) return;
    getDietGoalSettings(user.uid).then(setSettings).catch(console.error);
    // 摂取カロリー等はリアルタイム購読し、iOS側の記録も含めて即座に反映する
    const unsubscribe = subscribeToTodayIntakeSummary(user.uid, setIntake);
    return unsubscribe;
  }, [user]);

  const updateNumber = (key: keyof DietGoalSettings, value: string) => {
    if (!settings) return;
    setSettings({ ...settings, [key]: Number(value) });
  };

  const updateText = (key: keyof DietGoalSettings, value: string) => {
    if (!settings) return;
    setSettings({ ...settings, [key]: value });
  };

  const save = async () => {
    if (!user || !settings) return;
    setSaving(true);
    try {
      await saveDietGoalSettings(user.uid, settings);
    } finally {
      setSaving(false);
    }
  };

  if (!settings) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

  const startToCurrent = settings.currentWeightKg - settings.startWeightKg;
  const currentToGoal = settings.goalWeightKg - settings.currentWeightKg;
  const totalDays = daysBetween(settings.startDate, settings.goalDate);
  const todayStr = localDateKey();
  const elapsedDays = daysBetween(settings.startDate, todayStr);
  const remainingDays = daysBetween(todayStr, settings.goalDate);
  const schedulePct = totalDays > 0 ? Math.min(100, Math.round((elapsedDays / totalDays) * 100)) : 0;
  const weightPct = settings.startWeightKg !== settings.goalWeightKg
    ? Math.min(100, Math.max(0, Math.round(((settings.startWeightKg - settings.currentWeightKg) / (settings.startWeightKg - settings.goalWeightKg)) * 100)))
    : 0;

  // カロリー収支
  const todayCalories = intake?.calories ?? 0;
  const burnGoal = settings.dailyBurnKcalGoal ?? 0;
  const intakeGoal = settings.dailyIntakeKcalGoal ?? 0;
  const dailyBalance = todayCalories - burnGoal;
  const calPct = intakeGoal > 0 ? Math.min(100, Math.round((todayCalories / intakeGoal) * 100)) : 0;
  // 目標体重まで必要な週次カロリー赤字（7700kcal ≈ 1kg脂肪）
  const weeklyDeficitNeeded = remainingDays > 0 && currentToGoal < 0
    ? Math.round((Math.abs(currentToGoal) * 7700) / (remainingDays / 7))
    : 0;

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">
        <div className="duo-card p-5">
          <p className="text-duo-gray font-bold text-xs uppercase tracking-wider">GOAL</p>
          <h1 className="text-2xl font-black text-duo-dark">Diet Goal</h1>
          <p className="text-sm font-bold text-duo-gray mt-1">
            iOSと同じ考え方で、体重・体脂肪・カロリー計画をWebでも管理します。
          </p>
        </div>

        <div className="duo-card p-5">
          <div className="grid grid-cols-[1fr_auto_1fr_auto_1fr] items-center gap-2">
            <TimelinePoint title="スタート" date={settings.startDate} weight={settings.startWeightKg} bodyFat={settings.startBodyFatPercent} align="left" color="#3C3C3C" />
            <Delta value={startToCurrent} />
            <TimelinePoint title="今日" date="今日" weight={settings.currentWeightKg} bodyFat={settings.currentBodyFatPercent} align="center" color="#1CB0F6" large />
            <Delta value={currentToGoal} />
            <TimelinePoint title="ゴール" date={settings.goalDate} weight={settings.goalWeightKg} bodyFat={settings.goalBodyFatPercent} align="right" color="#58CC02" />
          </div>
          <div className="mt-5 grid grid-cols-2 gap-3">
            <ProgressTile label="期間進捗" value={schedulePct} />
            <ProgressTile label="体重進捗" value={weightPct} />
          </div>
          <p className="mt-4 text-center font-black text-duo-green">
            食事記録を続けよう！
          </p>
        </div>

        {/* カロリー収支カード */}
        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-4">🔥 今日のカロリー収支</h2>
          <div className="grid grid-cols-3 gap-2 mb-4">
            <div className="rounded-2xl p-3 text-center" style={{ background: '#FFF3E0' }}>
              <p className="text-[10px] font-black text-duo-gray">摂取</p>
              <p className="text-xl font-black" style={{ color: '#FF9600' }}>{todayCalories}</p>
              <p className="text-[9px] font-bold text-duo-gray">/ {intakeGoal || '—'} kcal</p>
            </div>
            <div className="rounded-2xl p-3 text-center" style={{ background: '#E8F5E9' }}>
              <p className="text-[10px] font-black text-duo-gray">消費目標</p>
              <p className="text-xl font-black text-duo-green">{burnGoal || '—'}</p>
              <p className="text-[9px] font-bold text-duo-gray">kcal</p>
            </div>
            <div className="rounded-2xl p-3 text-center" style={{ background: dailyBalance <= 0 ? '#E8F5E9' : '#FFF3E0' }}>
              <p className="text-[10px] font-black text-duo-gray">収支</p>
              <p className="text-xl font-black" style={{ color: dailyBalance <= 0 ? '#58CC02' : '#FF9600' }}>
                {dailyBalance >= 0 ? '+' : ''}{dailyBalance}
              </p>
              <p className="text-[9px] font-bold text-duo-gray">kcal</p>
            </div>
          </div>
          {intakeGoal > 0 && (
            <>
              <div className="duo-progress-bar mb-2" style={{ height: 8 }}>
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{ width: `${calPct}%`, background: calPct >= 100 ? '#FF4B4B' : '#FF9600' }}
                />
              </div>
              <p className="text-xs font-bold text-duo-gray text-right mb-3">{calPct}% 摂取</p>
            </>
          )}
          {weeklyDeficitNeeded > 0 && (
            <div className="rounded-xl px-3 py-2 flex items-start gap-2" style={{ background: '#E3F2FD', border: '1.5px solid #1CB0F6' }}>
              <span className="text-sm mt-0.5">📊</span>
              <p className="text-xs font-bold" style={{ color: '#0a6c96' }}>
                目標達成に必要な週次カロリー赤字: <span className="font-black">{weeklyDeficitNeeded.toLocaleString()} kcal/週</span>
                {remainingDays > 0 && ` · 残り${remainingDays}日`}
              </p>
            </div>
          )}
          {currentToGoal > 0 && (
            <div className="mt-2 rounded-xl px-3 py-2 flex items-start gap-2" style={{ background: '#FFF8E1', border: '1.5px solid #FFD900' }}>
              <span className="text-sm mt-0.5">💡</span>
              <p className="text-xs font-bold" style={{ color: '#7a5800' }}>
                目標体重より <span className="font-black">+{currentToGoal.toFixed(1)}kg</span> 多い状態です。食事記録と有酸素運動を継続しましょう。
              </p>
            </div>
          )}
          {currentToGoal <= 0 && settings.currentWeightKg > 0 && (
            <div className="mt-2 rounded-xl px-3 py-2 flex items-center gap-2" style={{ background: '#D7FFB8', border: '1.5px solid #58CC02' }}>
              <span className="text-sm">🎉</span>
              <p className="text-xs font-bold text-duo-green">目標体重を達成しています！</p>
            </div>
          )}
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">設定</h2>
          <div className="grid grid-cols-2 gap-3">
            <Field label="開始日" type="date" value={settings.startDate} onChange={v => updateText('startDate', v)} />
            <Field label="目標日" type="date" value={settings.goalDate} onChange={v => updateText('goalDate', v)} />
            <Field label="開始体重 kg" value={settings.startWeightKg} onChange={v => updateNumber('startWeightKg', v)} />
            <Field label="現在体重 kg" value={settings.currentWeightKg} onChange={v => updateNumber('currentWeightKg', v)} />
            <Field label="目標体重 kg" value={settings.goalWeightKg} onChange={v => updateNumber('goalWeightKg', v)} />
            <Field label="開始体脂肪 %" value={settings.startBodyFatPercent} onChange={v => updateNumber('startBodyFatPercent', v)} />
            <Field label="現在体脂肪 %" value={settings.currentBodyFatPercent} onChange={v => updateNumber('currentBodyFatPercent', v)} />
            <Field label="目標体脂肪 %" value={settings.goalBodyFatPercent} onChange={v => updateNumber('goalBodyFatPercent', v)} />
            <Field label="摂取目標 kcal" value={settings.dailyIntakeKcalGoal} onChange={v => updateNumber('dailyIntakeKcalGoal', v)} />
            <Field label="消費目標 kcal" value={settings.dailyBurnKcalGoal} onChange={v => updateNumber('dailyBurnKcalGoal', v)} />
          </div>
          <button onClick={save} disabled={saving} className="duo-btn-primary w-full mt-4">
            {saving ? '保存中...' : '保存する'}
          </button>
        </div>
      </div>
    </div>
  );
};

const TimelinePoint: React.FC<{
  title: string;
  date: string;
  weight: number;
  bodyFat: number;
  color: string;
  align: 'left' | 'center' | 'right';
  large?: boolean;
}> = ({ title, date, weight, bodyFat, color, align, large }) => (
  <div className={`text-${align}`}>
    <p className="text-xs font-black text-duo-dark">{title}</p>
    <p className="text-[10px] font-bold text-duo-gray">{date === '今日' ? date : new Date(date).toLocaleDateString('ja-JP', { month: 'numeric', day: 'numeric' })}</p>
    <p className={`${large ? 'text-4xl' : 'text-2xl'} font-black leading-tight`} style={{ color }}>{formatKg(weight)}</p>
    <p className="text-xs font-black text-duo-gray">体脂肪 {formatPercent(bodyFat)}</p>
  </div>
);

const Delta: React.FC<{ value: number }> = ({ value }) => (
  <div className="text-center">
    <p className="text-duo-gray font-black">→</p>
    <p className={`text-sm font-black ${value <= 0 ? 'text-duo-green' : 'text-duo-red'}`}>
      {value >= 0 ? '+' : ''}{value.toFixed(1)}kg
    </p>
  </div>
);

const ProgressTile: React.FC<{ label: string; value: number }> = ({ label, value }) => (
  <div className="rounded-2xl bg-duo-gray-light p-3">
    <div className="flex justify-between text-sm font-black text-duo-dark mb-2">
      <span>{label}</span>
      <span>{value}%</span>
    </div>
    <div className="duo-progress-bar" style={{ height: '10px' }}>
      <div className="duo-progress-fill" style={{ width: `${value}%` }} />
    </div>
  </div>
);

const Field: React.FC<{
  label: string;
  value: string | number;
  type?: string;
  onChange: (value: string) => void;
}> = ({ label, value, type = 'number', onChange }) => (
  <label className="block">
    <span className="text-xs font-black text-duo-gray">{label}</span>
    <input
      type={type}
      value={value}
      onChange={event => onChange(event.target.value)}
      className="mt-1 w-full rounded-xl border-2 border-duo-gray-mid px-3 py-2 font-bold text-duo-dark"
      step={type === 'number' ? '0.1' : undefined}
    />
  </label>
);
