import React, { useEffect, useMemo, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { getMindMetrics, saveMindMetrics } from '../services/wellnessService';
import type { MindMetrics } from '../types/wellness';

interface StressInfo {
  score: number;
  label: string;
  color: string;
}

function stressInfo(hrv: number): StressInfo {
  if (hrv <= 0) return { score: -1, label: '未入力', color: '#AFAFAF' };
  let score = 0;
  if (hrv >= 100) score = 5;
  else if (hrv >= 80) score = Math.round(5 + ((100 - hrv) / 20) * 10);
  else if (hrv >= 60) score = Math.round(15 + ((80 - hrv) / 20) * 20);
  else if (hrv >= 40) score = Math.round(35 + ((60 - hrv) / 20) * 25);
  else if (hrv >= 20) score = Math.round(60 + ((40 - hrv) / 20) * 20);
  else score = Math.round(Math.min(95, 80 + ((20 - hrv) / 20) * 15));

  if (score < 30) return { score, label: '低い', color: '#58CC02' };
  if (score < 55) return { score, label: '普通', color: '#78C800' };
  if (score < 75) return { score, label: 'やや高', color: '#FF9600' };
  return { score, label: '高い', color: '#FF4B4B' };
}

export const MindView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [metrics, setMetrics] = useState<MindMetrics | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) return;
    getMindMetrics(user.uid).then(setMetrics).catch(console.error);
  }, [user]);

  const currentStress = useMemo(() => stressInfo(metrics?.latestHRV ?? 0), [metrics?.latestHRV]);
  const averageStress = useMemo(() => stressInfo(metrics?.averageHRV || metrics?.latestHRV || 0), [metrics?.averageHRV, metrics?.latestHRV]);

  const recommendations = useMemo(() => {
    if (!metrics) return [];
    const items: { icon: string; text: string; color: string }[] = [];
    if (metrics.mindfulnessMinutes < 1) {
      items.push({ icon: '🫁', text: 'まだ深呼吸やマインドフルネスをしていません。1分だけ呼吸を整えてみましょう。', color: '#1CB0F6' });
    }
    if (metrics.standHours < 6 || metrics.steps < 5000) {
      items.push({ icon: '🚶', text: 'スタンド時間や歩数が少なめです。5分だけ歩く、階段を使うなどがおすすめです。', color: '#FF9600' });
    }
    if (averageStress.score >= 55) {
      items.push({ icon: '💆', text: 'こめかみ・首・肩を軽くマッサージして、体の緊張を落としてみましょう。', color: '#CE82FF' });
    }
    items.push({ icon: '☕', text: 'コーヒーを淹れる、水を飲む、歯磨きをするなど、小さな切り替えを入れましょう。', color: '#1CB0F6' });
    items.push({ icon: '🌤️', text: '遠くを見る、ぼおっとする、軽く息継ぎをするなど、いつもと違う休み方を試しましょう。', color: '#58CC02' });
    items.push({ icon: '🍃', text: '息抜きの時間を予定に入れて、通知や画面から少し離れてみましょう。', color: '#FF9600' });
    return items.slice(0, 6);
  }, [averageStress.score, metrics]);

  const update = (key: keyof MindMetrics, value: string) => {
    if (!metrics) return;
    setMetrics({ ...metrics, [key]: Number(value) });
  };

  const save = async () => {
    if (!user || !metrics) return;
    setSaving(true);
    try {
      await saveMindMetrics(user.uid, metrics);
    } finally {
      setSaving(false);
    }
  };

  if (!metrics) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">
        <div className="duo-card p-5" style={{ background: 'linear-gradient(135deg, #6D5DF6 0%, #1CB0F6 100%)' }}>
          <div className="flex items-center gap-3">
            <img src="/mascot.png" alt="Mindingo" className="w-10 h-10 rounded-full object-cover" />
            <div>
              <h1 className="text-2xl font-black text-white">Mindingo</h1>
              <p className="text-sm font-bold text-white/80">Webでは手入力・Firestore保存値でストレスを確認します。</p>
            </div>
          </div>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">現在のストレス</h2>
          <div className="grid grid-cols-3 gap-3">
            <Metric label="心拍数" value={metrics.latestHeartRate} unit="bpm" color="#FF4B4B" />
            <Metric label="HRV" value={metrics.latestHRV} unit="ms" color="#58CC02" />
            <StressTile stress={currentStress} />
          </div>
          <p className="mt-3 text-sm font-bold" style={{ color: currentStress.color }}>
            {currentStress.score >= 55
              ? 'ストレスが高めです。深呼吸を1分だけ試してみましょう。'
              : '今の状態は落ち着いています。こまめな水分補給と短い休憩で維持しましょう。'}
          </p>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">1日の平均</h2>
          <div className="grid grid-cols-3 gap-3">
            <Metric label="平均心拍" value={metrics.averageHeartRate} unit="bpm" color="#FF4B4B" />
            <Metric label="平均HRV" value={metrics.averageHRV} unit="ms" color="#58CC02" />
            <StressTile stress={averageStress} />
          </div>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">具体的にできること</h2>
          <div className="space-y-2">
            {recommendations.map((item, index) => (
              <div key={`${item.icon}-${index}`} className="rounded-xl p-3 flex gap-3" style={{ background: `${item.color}20` }}>
                <span className="text-xl">{item.icon}</span>
                <p className="text-sm font-bold text-duo-dark">{item.text}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="duo-card p-5">
          <h2 className="text-lg font-black text-duo-dark mb-3">手入力 / 同期データ</h2>
          <div className="grid grid-cols-2 gap-3">
            <Field label="現在心拍 bpm" value={metrics.latestHeartRate} onChange={v => update('latestHeartRate', v)} />
            <Field label="最新HRV ms" value={metrics.latestHRV} onChange={v => update('latestHRV', v)} />
            <Field label="平均心拍 bpm" value={metrics.averageHeartRate} onChange={v => update('averageHeartRate', v)} />
            <Field label="平均HRV ms" value={metrics.averageHRV} onChange={v => update('averageHRV', v)} />
            <Field label="マインドフルネス分" value={metrics.mindfulnessMinutes} onChange={v => update('mindfulnessMinutes', v)} />
            <Field label="スタンド時間" value={metrics.standHours} onChange={v => update('standHours', v)} />
            <Field label="歩数" value={metrics.steps} onChange={v => update('steps', v)} />
          </div>
          <button onClick={save} disabled={saving} className="duo-btn-primary w-full mt-4">
            {saving ? '保存中...' : '保存する'}
          </button>
        </div>
      </div>
    </div>
  );
};

const Metric: React.FC<{ label: string; value: number; unit: string; color: string }> = ({ label, value, unit, color }) => (
  <div className="rounded-2xl p-3 text-center" style={{ background: `${color}18` }}>
    <p className="text-xs font-black text-duo-gray">{label}</p>
    <p className="text-2xl font-black" style={{ color }}>{value > 0 ? value : '—'}</p>
    <p className="text-xs font-bold text-duo-gray">{unit}</p>
  </div>
);

const StressTile: React.FC<{ stress: StressInfo }> = ({ stress }) => (
  <div className="rounded-2xl p-3 text-center" style={{ background: `${stress.color}18` }}>
    <p className="text-xs font-black text-duo-gray">ストレス</p>
    <p className="text-2xl font-black" style={{ color: stress.color }}>{stress.score >= 0 ? stress.score : '—'}</p>
    <p className="text-xs font-bold" style={{ color: stress.color }}>{stress.label}</p>
  </div>
);

const Field: React.FC<{ label: string; value: number; onChange: (value: string) => void }> = ({ label, value, onChange }) => (
  <label className="block">
    <span className="text-xs font-black text-duo-gray">{label}</span>
    <input
      type="number"
      min={0}
      value={value}
      onChange={event => onChange(event.target.value)}
      className="mt-1 w-full rounded-xl border-2 border-duo-gray-mid px-3 py-2 font-bold text-duo-dark"
    />
  </label>
);
