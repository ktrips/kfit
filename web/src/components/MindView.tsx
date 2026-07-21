import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import {
  getMindMetrics,
  getTodayMindfulnessSessions,
  recordMindfulnessSession,
  saveMindMetrics,
} from '../services/wellnessService';
import { calculateStressScore, type StressScore } from '../utils/stress';
import type { MindfulnessSession, MindMetrics } from '../types/wellness';

const SESSION_CONFIG = {
  meditation: { label: '1分瞑想',    emoji: '🧘', duration: 60,  xp: 10, color: '#6D5DF6' },
  stretch:    { label: '3分ストレッチ', emoji: '🤸', duration: 180, xp: 30, color: '#58CC02' },
} as const;

type SessionType = keyof typeof SESSION_CONFIG;

function formatCountdown(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export const MindView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [metrics, setMetrics] = useState<MindMetrics | null>(null);
  const [saving, setSaving] = useState(false);
  const [sessions, setSessions] = useState<MindfulnessSession[]>([]);
  const [activeSession, setActiveSession] = useState<SessionType | null>(null);
  const [countdown, setCountdown] = useState(0);
  const completedRef = useRef(false);

  useEffect(() => {
    if (!user) return;
    getMindMetrics(user.uid).then(setMetrics).catch(console.error);
    getTodayMindfulnessSessions(user.uid).then(setSessions).catch(console.error);
  }, [user]);

  // Countdown timer
  useEffect(() => {
    if (!activeSession || countdown <= 0) return;
    const id = setTimeout(() => setCountdown(c => c - 1), 1000);
    return () => clearTimeout(id);
  }, [activeSession, countdown]);

  // Session completion when countdown reaches 0
  useEffect(() => {
    if (!activeSession || countdown !== 0 || completedRef.current) return;
    completedRef.current = true;

    const type = activeSession;
    const config = SESSION_CONFIG[type];
    setActiveSession(null);

    if (!user) { completedRef.current = false; return; }

    recordMindfulnessSession(user.uid, type, config.duration, config.xp)
      .then(newSession => {
        setSessions(prev => [newSession, ...prev]);
        setMetrics(prev => prev
          ? { ...prev, mindfulnessMinutes: (prev.mindfulnessMinutes || 0) + config.duration / 60 }
          : prev);
      })
      .catch(console.error)
      .finally(() => { completedRef.current = false; });
  }, [activeSession, countdown, user]);

  const startSession = (type: SessionType) => {
    if (activeSession) return;
    completedRef.current = false;
    setActiveSession(type);
    setCountdown(SESSION_CONFIG[type].duration);
  };

  const cancelSession = () => {
    completedRef.current = false;
    setActiveSession(null);
    setCountdown(0);
  };

  const currentStress = useMemo(() => calculateStressScore(metrics?.latestHRV ?? 0), [metrics?.latestHRV]);
  const averageStress = useMemo(
    () => calculateStressScore(metrics?.averageHRV || metrics?.latestHRV || 0),
    [metrics?.averageHRV, metrics?.latestHRV],
  );

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

  const todayXP = sessions.reduce((sum, s) => sum + s.xp, 0);

  if (!metrics) {
    return <div className="min-h-screen flex items-center justify-center font-black text-duo-green">読み込み中...</div>;
  }

  const activeConfig = activeSession ? SESSION_CONFIG[activeSession] : null;
  const progress = activeConfig ? 1 - countdown / activeConfig.duration : 0;

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">
        <div className="duo-card p-5" style={{ background: 'linear-gradient(135deg, #6D5DF6 0%, #1CB0F6 100%)' }}>
          <div className="flex items-center gap-3">
            <img src="/mascot.png" loading="lazy" alt="Mindingo" className="w-10 h-10 rounded-full object-cover" />
            <div>
              <h1 className="text-2xl font-black text-white">Mindingo</h1>
              <p className="text-sm font-bold text-white/80">Webでは手入力・Firestore保存値でストレスを確認します。</p>
            </div>
          </div>
        </div>

        {/* Mindfulness Session Card */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-black text-duo-dark">🧘 マインドフルネス</h2>
            {todayXP > 0 && (
              <span className="text-sm font-black px-2 py-1 rounded-full"
                style={{ background: '#FFD90020', color: '#CC8800' }}>
                今日 +{todayXP} XP
              </span>
            )}
          </div>

          {!activeSession ? (
            <div className="grid grid-cols-2 gap-3">
              {(Object.entries(SESSION_CONFIG) as [SessionType, (typeof SESSION_CONFIG)[SessionType]][]).map(([type, config]) => (
                <button
                  key={type}
                  onClick={() => startSession(type)}
                  className="rounded-2xl p-4 text-center transition-transform active:scale-95 cursor-pointer"
                  style={{ background: `${config.color}18`, border: `2px solid ${config.color}40` }}
                >
                  <div className="text-3xl mb-1">{config.emoji}</div>
                  <div className="font-black text-duo-dark text-sm">{config.label}</div>
                  <div
                    className="text-xs font-bold mt-1 rounded-full px-2 py-0.5 inline-block"
                    style={{ background: `${config.color}30`, color: config.color }}
                  >
                    +{config.xp} XP
                  </div>
                </button>
              ))}
            </div>
          ) : (
            <div className="text-center py-2">
              <div className="text-5xl mb-2">{activeConfig!.emoji}</div>
              <p className="font-black text-duo-dark">{activeConfig!.label}</p>
              <p className="text-5xl font-black mt-2" style={{ color: activeConfig!.color }}>
                {formatCountdown(countdown)}
              </p>
              <div className="w-full bg-gray-100 rounded-full h-3 my-4">
                <div
                  className="h-3 rounded-full transition-all duration-1000"
                  style={{ width: `${progress * 100}%`, backgroundColor: activeConfig!.color }}
                />
              </div>
              <button
                onClick={cancelSession}
                className="text-sm font-bold text-duo-gray underline"
              >
                キャンセル
              </button>
            </div>
          )}

          {sessions.length > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-100">
              <p className="text-xs font-black text-duo-gray mb-2">今日のセッション</p>
              <div className="space-y-2">
                {sessions.map(session => (
                  <div
                    key={session.id}
                    className="flex items-center justify-between rounded-xl px-3 py-2"
                    style={{ background: session.type === 'meditation' ? '#6D5DF608' : '#58CC0208' }}
                  >
                    <div className="flex items-center gap-2">
                      <span>{session.type === 'meditation' ? '🧘' : '🤸'}</span>
                      <span className="text-sm font-bold text-duo-dark">{session.label}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-duo-gray">
                        {session.timestamp.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}
                      </span>
                      <span
                        className="text-xs font-black px-2 py-0.5 rounded-full"
                        style={{
                          background: session.type === 'meditation' ? '#6D5DF620' : '#58CC0220',
                          color: session.type === 'meditation' ? '#6D5DF6' : '#58CC02',
                        }}
                      >
                        +{session.xp} XP
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
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

const StressTile: React.FC<{ stress: StressScore }> = ({ stress }) => (
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
