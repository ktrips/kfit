import React, { useEffect, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { getDietGoalSettings, saveDietGoalSettings } from '../services/wellnessService';
import type { DietGoalSettings } from '../types/wellness';

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
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) return;
    getDietGoalSettings(user.uid).then(setSettings).catch(console.error);
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
  const elapsedDays = daysBetween(settings.startDate, new Date().toISOString().split('T')[0]);
  const schedulePct = totalDays > 0 ? Math.min(100, Math.round((elapsedDays / totalDays) * 100)) : 0;
  const weightPct = settings.startWeightKg !== settings.goalWeightKg
    ? Math.min(100, Math.max(0, Math.round(((settings.startWeightKg - settings.currentWeightKg) / (settings.startWeightKg - settings.goalWeightKg)) * 100)))
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
