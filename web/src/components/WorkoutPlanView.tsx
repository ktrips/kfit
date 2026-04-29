import React, { useState } from 'react';
import { useAppStore } from '../store/appStore';
import { recordExercise, getUserProfile } from '../services/firebase';

// ── データ定義 ────────────────────────────────────────────────────────────────

interface PlannedExercise {
  id: string;
  name: string;
  reps: string;
  emoji: string;
  exerciseId: string;
  repCount: number;
}

interface CardioSession {
  type: string;
  detail: string;
  emoji: string;
}

const PHASE1_CIRCUIT: PlannedExercise[] = [
  { id: 'p1-squat',    name: 'スクワット',             reps: '20回',       emoji: '🏋️', exerciseId: 'squat',  repCount: 20 },
  { id: 'p1-pushup',   name: '腕立て伏せ',             reps: '15回',       emoji: '💪', exerciseId: 'pushup', repCount: 15 },
  { id: 'p1-legraise', name: 'レッグレイズ',           reps: '15回',       emoji: '🔥', exerciseId: 'situp',  repCount: 15 },
  { id: 'p1-plank',    name: 'プランク',               reps: '45秒',       emoji: '🧘', exerciseId: 'plank',  repCount: 45 },
  { id: 'p1-bulg',     name: 'ブルガリアンスクワット', reps: '10回×片足', emoji: '🦵', exerciseId: 'lunge',  repCount: 20 },
];

const PHASE2_UPPER: PlannedExercise[] = [
  { id: 'p2-press',  name: '腕立て・ダンベルプレス', reps: '3セット 限界', emoji: '💪', exerciseId: 'pushup', repCount: 12 },
  { id: 'p2-row',    name: '懸垂・ローイング',       reps: '3セット 限界', emoji: '🏋️', exerciseId: 'pushup', repCount: 10 },
  { id: 'p2-should', name: 'ショルダープレス',       reps: '3セット 限界', emoji: '🙌', exerciseId: 'pushup', repCount: 12 },
];

const PHASE2_LOWER: PlannedExercise[] = [
  { id: 'p2-goblet',    name: 'スクワット・ゴブレット', reps: '3セット 限界', emoji: '🏋️', exerciseId: 'squat',  repCount: 15 },
  { id: 'p2-lunge',    name: 'ランジ',                 reps: '3セット 限界', emoji: '🦵', exerciseId: 'lunge',  repCount: 12 },
  { id: 'p2-legraise', name: 'レッグレイズ',           reps: '3セット 限界', emoji: '🔥', exerciseId: 'situp',  repCount: 15 },
  { id: 'p2-plank',    name: 'プランク',               reps: '3セット 限界', emoji: '🧘', exerciseId: 'plank',  repCount: 45 },
];

// weekday: Sun=0, Mon=1, ..., Sat=6
const WEEKLY_CARDIO: Record<number, CardioSession> = {
  1: { type: 'バイク',  detail: '軽め 30km', emoji: '🚴' },
  2: { type: 'ラン',    detail: '5km',       emoji: '🏃' },
  3: { type: 'スイム',  detail: '1km',       emoji: '🏊' },
  5: { type: 'ラン',    detail: '5km',       emoji: '🏃' },
  6: { type: 'バイク',  detail: '長め 70km', emoji: '🚴' },
  0: { type: 'スイム',  detail: '1km',       emoji: '🏊' },
};

// ── Quick Record Modal ────────────────────────────────────────────────────────

interface QuickRecordModalProps {
  exercise: PlannedExercise;
  onClose: () => void;
  onDone: () => void;
}

const QuickRecordModal: React.FC<QuickRecordModalProps> = ({ exercise, onClose, onDone }) => {
  const user = useAppStore((s) => s.user);
  const setUserProfile = useAppStore((s) => s.setUserProfile);
  const [reps, setReps] = useState(exercise.repCount);
  const [saving, setSaving] = useState(false);
  const points = reps * 2;

  const handleSave = async () => {
    if (!user) return;
    setSaving(true);
    try {
      await recordExercise(user.uid, {
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.name,
        reps,
        points,
      });
      const profile = await getUserProfile(user.uid);
      if (profile) setUserProfile(profile as any);
      onDone();
    } catch (e) {
      console.error(e);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center" style={{ background: 'rgba(0,0,0,0.4)' }}>
      <div
        className="w-full max-w-md rounded-t-3xl p-6 flex flex-col gap-5"
        style={{ background: 'white', paddingBottom: 'calc(1.5rem + env(safe-area-inset-bottom))' }}
      >
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-black text-duo-dark">記録する</h3>
          <button onClick={onClose} className="text-2xl text-duo-gray leading-none">✕</button>
        </div>

        <div className="flex items-center gap-4 p-4 rounded-2xl" style={{ background: '#F7F7F7' }}>
          <span className="text-4xl">{exercise.emoji}</span>
          <div>
            <p className="font-black text-duo-dark">{exercise.name}</p>
            <p className="text-duo-gray font-bold text-sm">{exercise.reps}</p>
          </div>
        </div>

        <div className="flex items-center justify-center gap-6">
          <button
            onClick={() => setReps(Math.max(1, reps - 1))}
            className="w-14 h-14 rounded-2xl text-3xl font-black flex items-center justify-center"
            style={{ background: '#E5E5E5', color: '#AFAFAF' }}
          >
            −
          </button>
          <div className="text-center">
            <p className="text-5xl font-black" style={{ color: '#58CC02', lineHeight: 1 }}>{reps}</p>
            <p className="text-duo-gray font-bold text-xs mt-1">rep</p>
          </div>
          <button
            onClick={() => setReps(reps + 1)}
            className="w-14 h-14 rounded-2xl text-3xl font-black flex items-center justify-center"
            style={{ background: '#E8F5E9', color: '#58CC02' }}
          >
            ＋
          </button>
        </div>

        <p className="text-center font-extrabold" style={{ color: '#CE9700' }}>
          +{points} XP 獲得！
        </p>

        <button
          onClick={handleSave}
          disabled={saving}
          className="duo-btn-primary text-base w-full"
        >
          {saving ? '記録中…' : '✅ 記録する'}
        </button>
      </div>
    </div>
  );
};

// ── Main View ─────────────────────────────────────────────────────────────────

export const WorkoutPlanView: React.FC = () => {
  const userProfile = useAppStore((s) => s.userProfile);
  const [doneIds, setDoneIds] = useState<Set<string>>(new Set());
  const [recording, setRecording] = useState<PlannedExercise | null>(null);

  const dayOfWeek = new Date().getDay();

  const joinDate: Date = userProfile?.joinDate
    ? (userProfile.joinDate instanceof Date ? userProfile.joinDate : new Date((userProfile.joinDate as any).toDate?.() ?? userProfile.joinDate))
    : new Date();

  const daysSinceJoin = Math.max(0, Math.floor((Date.now() - joinDate.getTime()) / 86400000));
  const phase = daysSinceJoin >= 90 ? 2 : 1;
  const phaseProgress = phase === 1
    ? Math.min(daysSinceJoin / 90, 1)
    : Math.min((daysSinceJoin - 90) / 90, 1);

  const isUpperDay = dayOfWeek % 2 === 0;
  const todayExercises: PlannedExercise[] =
    phase === 1 ? PHASE1_CIRCUIT : (isUpperDay ? PHASE2_UPPER : PHASE2_LOWER);

  const todayCardio = WEEKLY_CARDIO[dayOfWeek];

  const handleCheck = (ex: PlannedExercise) => {
    if (doneIds.has(ex.id)) {
      setDoneIds(prev => { const s = new Set(prev); s.delete(ex.id); return s; });
    } else {
      setRecording(ex);
    }
  };

  const handleRecordDone = (ex: PlannedExercise) => {
    setDoneIds(prev => new Set(prev).add(ex.id));
    setRecording(null);
  };

  const allDone = todayExercises.length > 0 && doneIds.size >= todayExercises.length;

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">

        {/* フェーズカード */}
        <div className="duo-card p-5">
          <div className="flex items-start justify-between mb-3">
            <div className="flex flex-col gap-1">
              <span
                className="text-xs font-extrabold px-3 py-1 rounded-full w-fit"
                style={{ background: '#E8F5E9', color: '#46A302' }}
              >
                フェーズ {phase}
              </span>
              <p className="font-black text-duo-dark text-base">
                {phase === 1 ? '0〜3ヶ月：体脂肪 20%→17%' : '3〜6ヶ月：体脂肪 17%→15%'}
              </p>
            </div>
            <span
              className="text-xs font-extrabold px-3 py-1.5 rounded-xl text-white shrink-0"
              style={{ background: '#FF9600' }}
            >
              {phase === 1 ? '15分サーキット' : (isUpperDay ? '上半身の日' : '下半身＋腹筋')}
            </span>
          </div>

          <div className="duo-progress-bar mb-2">
            <div
              className="h-full rounded-full transition-all duration-700"
              style={{
                width: `${phaseProgress * 100}%`,
                background: 'linear-gradient(90deg, #58CC02, #1CB0F6)',
              }}
            />
          </div>
          <p className="text-duo-gray font-bold text-xs">🎯 6ヶ月で体脂肪 -5%、1年で6パックへ</p>
        </div>

        {/* 有酸素カード */}
        {todayCardio && (
          <div className="duo-card p-4 flex items-center gap-4">
            <div
              className="w-14 h-14 rounded-2xl flex items-center justify-center text-3xl shrink-0"
              style={{ background: '#E3F2FD' }}
            >
              {todayCardio.emoji}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-duo-gray font-bold text-xs">今日の有酸素</p>
              <p className="font-black text-duo-dark">
                {todayCardio.type} {todayCardio.detail}
              </p>
            </div>
            <span className="text-2xl opacity-30">✅</span>
          </div>
        )}

        {/* 筋トレカード */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-2">
            <h2 className="font-black text-duo-dark text-lg">
              {phase === 1 ? '💥 15分サーキット × 3周' : '💪 分割トレーニング'}
            </h2>
            <span className="font-extrabold text-sm" style={{ color: '#58CC02' }}>
              {doneIds.size}/{todayExercises.length}
            </span>
          </div>

          {phase === 1 && (
            <p className="text-xs font-extrabold mb-3" style={{ color: '#FF9600' }}>
              インターバルなし・最後は限界まで！
            </p>
          )}

          <div className="space-y-2">
            {todayExercises.map((ex) => {
              const done = doneIds.has(ex.id);
              return (
                <div
                  key={ex.id}
                  className="flex items-center gap-3 rounded-2xl p-3 transition-all"
                  style={{
                    background: done ? 'rgba(88,204,2,0.06)' : '#F7F7F7',
                    border: `2px solid ${done ? 'rgba(88,204,2,0.2)' : '#e5e5e5'}`,
                  }}
                >
                  <div
                    className="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
                    style={{ background: done ? 'rgba(88,204,2,0.15)' : '#E5E5E5' }}
                  >
                    {ex.emoji}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p
                      className="font-extrabold text-sm"
                      style={{
                        color: done ? '#AFAFAF' : '#3C3C3C',
                        textDecoration: done ? 'line-through' : 'none',
                      }}
                    >
                      {ex.name}
                    </p>
                    <p className="text-duo-gray font-bold text-xs">{ex.reps}</p>
                  </div>
                  <button
                    onClick={() => handleCheck(ex)}
                    className="text-2xl transition-transform active:scale-90"
                    aria-label={done ? '取り消し' : '記録する'}
                  >
                    {done ? (
                      <span style={{ color: '#58CC02' }}>✅</span>
                    ) : (
                      <span style={{ color: '#AFAFAF' }}>⭕</span>
                    )}
                  </button>
                </div>
              );
            })}
          </div>

          {allDone && (
            <div
              className="mt-3 py-3 rounded-2xl text-center font-black text-sm"
              style={{ background: 'rgba(88,204,2,0.08)', color: '#46A302' }}
            >
              🎉 今日のメニュー完了！すごい！
            </div>
          )}
        </div>

        {/* 栄養目標カード */}
        <div className="duo-card p-5">
          <h2 className="font-black text-duo-dark text-lg mb-3">🍽 今日の栄養目標</h2>
          <div className="grid grid-cols-2 gap-2">
            {[
              { label: 'カロリー',   value: '1900〜2100', unit: 'kcal', bg: '#FFF3E0', color: '#FF9600' },
              { label: 'タンパク質', value: '130〜150',   unit: 'g',    bg: '#E8F5E9', color: '#46A302' },
              { label: '脂質',       value: '40〜55',     unit: 'g',    bg: '#FFF8E1', color: '#CE9700' },
              { label: '炭水化物',   value: '200〜250',   unit: 'g',    bg: '#E3F2FD', color: '#1CB0F6' },
            ].map(({ label, value, unit, bg, color }) => (
              <div
                key={label}
                className="rounded-2xl p-3 flex flex-col items-center text-center"
                style={{ background: bg }}
              >
                <p className="text-xs font-extrabold" style={{ color }}>{label}</p>
                <p className="text-lg font-black" style={{ color }}>{value}</p>
                <p className="text-xs font-bold" style={{ color, opacity: 0.7 }}>{unit}</p>
              </div>
            ))}
          </div>

          <div className="mt-3 space-y-1">
            {[
              '🌅 朝：プロテイン＋バナナ＋ゆで卵',
              '🍱 昼：鶏胸肉 200g＋ご飯 150g＋サラダ',
              '🌙 夜：魚 or 鶏＋野菜たっぷり（炭水化物少なめ）',
              '⚡ トレ後：プロテイン 30分以内',
            ].map((tip) => (
              <p key={tip} className="text-xs font-bold text-duo-gray">{tip}</p>
            ))}
          </div>
        </div>

        {/* ポイント解説 */}
        <div className="duo-card p-4">
          <h2 className="font-black text-duo-dark text-base mb-2">💡 成功のカギ</h2>
          <div className="space-y-1.5">
            {[
              { icon: '🔥', text: '「楽な15分」より「キツい15分」が結果を決める' },
              { icon: '💧', text: '水を1日2〜2.5L飲む' },
              { icon: '🕐', text: '20時〜翌8時は食べない（12〜14時間断食）' },
              { icon: '🥩', text: 'タンパク質は1回30g × 4回に分けて摂る' },
            ].map(({ icon, text }) => (
              <div key={text} className="flex items-start gap-2">
                <span className="text-base leading-tight">{icon}</span>
                <p className="text-xs font-bold text-duo-gray leading-snug">{text}</p>
              </div>
            ))}
          </div>
        </div>

      </div>

      {/* Quick Record Modal */}
      {recording && (
        <QuickRecordModal
          exercise={recording}
          onClose={() => setRecording(null)}
          onDone={() => handleRecordDone(recording)}
        />
      )}
    </div>
  );
};
