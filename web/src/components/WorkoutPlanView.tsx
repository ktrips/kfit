import React, { useState, useEffect } from 'react';
import { useAppStore } from '../store/appStore';
import { recordExercise } from '../services/firebase';
import { CreatePlanModal } from './CreatePlanModal';
import {
  getSavedPlans, deletePlan,
  type AIGeneratedPlan,
  PROVIDER_LABELS,
} from '../services/aiService';

// ── データ定義 ────────────────────────────────────────────────────────────────

interface PlannedExercise {
  id: string;
  name: string;
  reps: string;
  emoji: string;
  exerciseId: string;
  repCount: number;
  description: string;
  tips: string[];
  muscles: string[];
  difficulty: '初級' | '中級' | '上級';
}

interface CardioSession {
  type: string;
  detail: string;
  emoji: string;
}

const PHASE1_CIRCUIT: PlannedExercise[] = [
  {
    id: 'p1-squat', name: 'スクワット', reps: '20回', emoji: '🏋️',
    exerciseId: 'squat', repCount: 20, difficulty: '初級',
    description: '下半身の王様。太もも・お尻を鍛える基本種目。毎日やっても疲れにくく、脂肪燃焼にも効果的。',
    tips: ['足を肩幅に開く', 'つま先はやや外向き', '膝がつま先より前に出ないように', 'お尻を後ろに引くイメージで下げる', '太ももが床と平行になるまで下げる'],
    muscles: ['大腿四頭筋', '大殿筋', 'ハムストリングス'],
  },
  {
    id: 'p1-pushup', name: '腕立て伏せ', reps: '15回', emoji: '💪',
    exerciseId: 'pushup', repCount: 15, difficulty: '初級',
    description: '胸・肩・三頭筋を一度に鍛えられる全身種目。フォームを正確に保つことが最大の効果につながる。',
    tips: ['手は肩幅より少し広め', '体を一直線に保つ', '胸が床に触れるまで下げる', 'ひじを90度まで曲げる', '腰が落ちないように注意'],
    muscles: ['大胸筋', '三角筋前部', '上腕三頭筋'],
  },
  {
    id: 'p1-legraise', name: 'レッグレイズ', reps: '15回', emoji: '🔥',
    exerciseId: 'situp', repCount: 15, difficulty: '初級',
    description: '下腹部を集中的に鍛える種目。反動を使わず、腹筋の力だけで足を上げるのがポイント。',
    tips: ['仰向けで腰を床につける', '足をゆっくり上げ下げする', '足が床につく直前で止める', '呼吸は足を上げるときに吐く', '首を前に出さない'],
    muscles: ['腸腰筋', '下腹部', '腹直筋'],
  },
  {
    id: 'p1-plank', name: 'プランク', reps: '45秒', emoji: '🧘',
    exerciseId: 'plank', repCount: 45, difficulty: '初級',
    description: '体幹全体を等尺性収縮で鍛える種目。姿勢改善・腰痛予防にも効果的。',
    tips: ['ひじは肩の真下に置く', '体を一直線に保つ', 'お尻が上がらないように', '視線は床に向ける', '呼吸を止めない'],
    muscles: ['腹横筋', '脊柱起立筋', '大殿筋'],
  },
  {
    id: 'p1-bulg', name: 'ブルガリアンスクワット', reps: '10回×片足', emoji: '🦵',
    exerciseId: 'lunge', repCount: 20, difficulty: '中級',
    description: '片足スクワット。通常のスクワットより高強度で、左右の筋力バランスを整える効果がある。',
    tips: ['後ろ足をベンチ・椅子に乗せる', '前足は股関節の真下あたり', '膝が内側に入らないように', '上体はやや前傾', '前足のかかとで踏みしめる'],
    muscles: ['大腿四頭筋', '大殿筋', 'ハムストリングス', '腸腰筋'],
  },
];

const PHASE2_UPPER: PlannedExercise[] = [
  {
    id: 'p2-press', name: '腕立て・ダンベルプレス', reps: '3セット 限界', emoji: '💪',
    exerciseId: 'pushup', repCount: 12, difficulty: '中級',
    description: '大胸筋の主力種目。限界まで追い込むことで筋肥大を狙う。ダンベルがあればより可動域を広げられる。',
    tips: ['ダンベルなら乳頭ライン付近でおろす', '肩甲骨を寄せて胸を張る', '下げるときゆっくり2秒', '上げるとき1秒で爆発的に', 'インターバル90〜120秒'],
    muscles: ['大胸筋', '三角筋前部', '上腕三頭筋'],
  },
  {
    id: 'p2-row', name: '懸垂・ローイング', reps: '3セット 限界', emoji: '🏋️',
    exerciseId: 'pushup', repCount: 10, difficulty: '上級',
    description: '背中の厚みをつくる引く系種目。懸垂ができない場合はテーブルロウで代替可能。',
    tips: ['懸垂：肩幅より広めに握る', 'あごがバーを超えるまで引く', 'テーブルロウ：斜め懸垂でも効果的', '肩甲骨を使って背中で引く意識', 'ネガティブ（下げる）を2秒かけて'],
    muscles: ['広背筋', '大円筋', '上腕二頭筋', '菱形筋'],
  },
  {
    id: 'p2-should', name: 'ショルダープレス', reps: '3セット 限界', emoji: '🙌',
    exerciseId: 'pushup', repCount: 12, difficulty: '中級',
    description: '肩の丸みを作る種目。ペットボトルでも代替できる。三角筋中部・前部を鍛える。',
    tips: ['ひじは90度で耳の横あたり', '真上に向かって押し上げる', '腰を反りすぎない', '下げるとき肩より低くしない', '首をすくめないよう注意'],
    muscles: ['三角筋', '上腕三頭筋', '僧帽筋上部'],
  },
];

const PHASE2_LOWER: PlannedExercise[] = [
  {
    id: 'p2-goblet', name: 'スクワット・ゴブレット', reps: '3セット 限界', emoji: '🏋️',
    exerciseId: 'squat', repCount: 15, difficulty: '中級',
    description: '重りを胸の前で抱えるスクワット。深くしゃがめて股関節の可動域が広がり、姿勢が安定する。',
    tips: ['ダンベルやペットボトルを両手で胸前に', '深くしゃがむほど効果的', 'ひじが内側の太ももに当たるイメージ', '背中をまっすぐ保つ', '息を吸いながら下げる'],
    muscles: ['大腿四頭筋', '大殿筋', '内転筋'],
  },
  {
    id: 'p2-lunge', name: 'ランジ', reps: '3セット 限界', emoji: '🦵',
    exerciseId: 'lunge', repCount: 12, difficulty: '中級',
    description: '前後にステップして片足ずつ鍛えるバランス系種目。ヒップアップ効果が高い。',
    tips: ['大股で一歩踏み出す', '前膝が90度になるまで下げる', '後ろ膝は床スレスレまで', '上体は真っすぐ保つ', '左右交互にリズムよく'],
    muscles: ['大腿四頭筋', '大殿筋', 'ハムストリングス'],
  },
  {
    id: 'p2-legraise2', name: 'レッグレイズ', reps: '3セット 限界', emoji: '🔥',
    exerciseId: 'situp', repCount: 15, difficulty: '初級',
    description: '下腹部を集中的に鍛える種目。反動を使わず、腹筋の力だけで足を上げる。',
    tips: ['仰向けで腰を床につける', '足をゆっくり上げ下げ', '足が床につく直前で止める', '呼吸は足を上げるときに吐く', '首を前に出さない'],
    muscles: ['腸腰筋', '下腹部', '腹直筋'],
  },
  {
    id: 'p2-plank2', name: 'プランク', reps: '3セット 限界', emoji: '🧘',
    exerciseId: 'plank', repCount: 45, difficulty: '初級',
    description: '体幹全体を等尺性収縮で鍛える。姿勢改善・腰痛予防にも効果的。',
    tips: ['ひじは肩の真下', '体を一直線に', 'お尻が上がらないように', '視線は床', '呼吸を止めない'],
    muscles: ['腹横筋', '脊柱起立筋', '大殿筋'],
  },
];

const WEEKLY_CARDIO: Record<number, CardioSession> = {
  1: { type: 'バイク',  detail: '軽め 30km', emoji: '🚴' },
  2: { type: 'ラン',    detail: '5km',       emoji: '🏃' },
  3: { type: 'スイム',  detail: '1km',       emoji: '🏊' },
  5: { type: 'ラン',    detail: '5km',       emoji: '🏃' },
  6: { type: 'バイク',  detail: '長め 70km', emoji: '🚴' },
  0: { type: 'スイム',  detail: '1km',       emoji: '🏊' },
};

const DIFFICULTY_COLOR: Record<PlannedExercise['difficulty'], { bg: string; text: string }> = {
  '初級': { bg: '#D7FFB8', text: '#2d7a00' },
  '中級': { bg: '#FFF3E0', text: '#8a4700' },
  '上級': { bg: '#FCE4EC', text: '#7f0000' },
};

// ── Exercise Detail Sheet ─────────────────────────────────────────────────────

interface DetailSheetProps {
  exercise: PlannedExercise;
  onClose: () => void;
  onRecorded: (id: string) => void;
}

const DetailSheet: React.FC<DetailSheetProps> = ({ exercise, onClose, onRecorded }) => {
  const user = useAppStore((s) => s.user);
  const [reps, setReps] = useState(exercise.repCount);
  const [tab, setTab] = useState<'detail' | 'record'>('detail');
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);
  const diff = DIFFICULTY_COLOR[exercise.difficulty];
  const pts = reps * 2;

  const handleSave = async () => {
    if (!user) return;
    setSaving(true);
    try {
      await recordExercise(user.uid, {
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.name,
        reps,
        points: pts,
        formScore: 85,
      });
      setDone(true);
      setTimeout(() => { onRecorded(exercise.id); onClose(); }, 1200);
    } catch (e) {
      console.error(e);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center"
      style={{ background: 'rgba(0,0,0,0.45)' }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className="w-full max-w-md rounded-t-3xl flex flex-col"
        style={{
          background: 'white',
          maxHeight: '90vh',
          paddingBottom: 'calc(1.5rem + env(safe-area-inset-bottom))',
        }}
      >
        {/* Handle */}
        <div className="flex justify-center pt-3 pb-1">
          <div className="w-10 h-1 rounded-full" style={{ background: '#e5e5e5' }} />
        </div>

        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-3">
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center text-4xl shrink-0"
            style={{ background: '#F7F7F7' }}
          >
            {exercise.emoji}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-0.5">
              <h3 className="font-black text-duo-dark text-lg leading-tight">{exercise.name}</h3>
              <span
                className="text-xs font-extrabold px-2 py-0.5 rounded-full shrink-0"
                style={{ background: diff.bg, color: diff.text }}
              >
                {exercise.difficulty}
              </span>
            </div>
            <p className="text-duo-gray font-bold text-sm">{exercise.reps}</p>
          </div>
          <button onClick={onClose} className="text-2xl text-duo-gray leading-none shrink-0">✕</button>
        </div>

        {/* Tabs */}
        <div className="flex mx-5 mb-3 rounded-xl overflow-hidden" style={{ border: '2px solid #e5e5e5' }}>
          {(['detail', 'record'] as const).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className="flex-1 py-2 font-extrabold text-sm transition-all"
              style={{
                background: tab === t ? '#58CC02' : 'white',
                color: tab === t ? 'white' : '#AFAFAF',
              }}
            >
              {t === 'detail' ? '📖 詳細' : '✏️ 記録'}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="overflow-y-auto px-5 pb-2 flex-1">
          {tab === 'detail' ? (
            <div className="space-y-4">
              {/* Description */}
              <div
                className="rounded-2xl p-4"
                style={{ background: '#F7F7F7', border: '1.5px solid #e5e5e5' }}
              >
                <p className="text-duo-dark font-bold text-sm leading-relaxed">{exercise.description}</p>
              </div>

              {/* Muscles */}
              <div>
                <p className="font-extrabold text-duo-gray text-xs uppercase tracking-wider mb-2">鍛える部位</p>
                <div className="flex flex-wrap gap-2">
                  {exercise.muscles.map(m => (
                    <span
                      key={m}
                      className="px-3 py-1 rounded-full font-extrabold text-xs"
                      style={{ background: '#E8F5E9', color: '#2d7a00' }}
                    >
                      {m}
                    </span>
                  ))}
                </div>
              </div>

              {/* Tips */}
              <div>
                <p className="font-extrabold text-duo-gray text-xs uppercase tracking-wider mb-2">フォームのコツ</p>
                <div className="space-y-2">
                  {exercise.tips.map((tip, i) => (
                    <div key={i} className="flex items-start gap-2">
                      <span
                        className="w-5 h-5 rounded-full flex items-center justify-center font-black text-xs shrink-0 mt-0.5"
                        style={{ background: '#58CC02', color: 'white' }}
                      >
                        {i + 1}
                      </span>
                      <p className="font-bold text-duo-dark text-sm leading-snug">{tip}</p>
                    </div>
                  ))}
                </div>
              </div>

              <button
                onClick={() => setTab('record')}
                className="duo-btn-primary w-full text-base mt-2"
              >
                ✏️ このトレーニングを記録する
              </button>
            </div>
          ) : (
            <div className="space-y-5">
              {done ? (
                <div className="text-center py-8 flex flex-col items-center gap-3">
                  <div className="text-6xl animate-bounce_in">✅</div>
                  <p className="font-black text-duo-green text-xl">記録完了！</p>
                  <p className="font-extrabold" style={{ color: '#CE9700' }}>+{pts} XP 獲得！</p>
                </div>
              ) : (
                <>
                  <div>
                    <p className="text-duo-gray font-extrabold text-xs uppercase tracking-wider mb-3 text-center">
                      rep 数を調整
                    </p>
                    <div className="flex items-center justify-center gap-6">
                      <button
                        onClick={() => setReps(r => Math.max(1, r - 1))}
                        className="w-14 h-14 rounded-2xl font-black text-3xl flex items-center justify-center"
                        style={{ background: '#E5E5E5', color: '#AFAFAF', boxShadow: '0 4px 0 #c0c0c0' }}
                      >
                        −
                      </button>
                      <div className="text-center">
                        <p className="text-7xl font-black leading-none" style={{ color: '#58CC02' }}>{reps}</p>
                        <p className="text-duo-gray font-bold text-xs mt-1">rep</p>
                      </div>
                      <button
                        onClick={() => setReps(r => r + 1)}
                        className="w-14 h-14 rounded-2xl font-black text-3xl flex items-center justify-center"
                        style={{ background: '#D7FFB8', color: '#46A302', boxShadow: '0 4px 0 #46A302' }}
                      >
                        ＋
                      </button>
                    </div>
                    <p className="text-center font-extrabold mt-3" style={{ color: '#CE9700' }}>
                      +{pts} XP
                    </p>
                  </div>

                  <button
                    onClick={handleSave}
                    disabled={saving}
                    className="duo-btn-primary w-full text-lg py-4"
                  >
                    {saving ? '記録中…' : '✅ 記録する'}
                  </button>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

// ── Main View ─────────────────────────────────────────────────────────────────

export const WorkoutPlanView: React.FC = () => {
  const userProfile = useAppStore((s) => s.userProfile);
  const [r1Done, setR1Done] = useState<Set<string>>(new Set());
  const [r2Done, setR2Done] = useState<Set<string>>(new Set());
  const [selected, setSelected] = useState<PlannedExercise | null>(null);
  const [selectedRound, setSelectedRound] = useState<1 | 2>(1);

  const hour = new Date().getHours();
  const isMorning = hour < 12;

  // ── AIプランタブ ─────────────────────────────────────────────────────────
  const [activeTab, setActiveTab] = useState<'standard' | 'ai'>('standard');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [savedPlans, setSavedPlans] = useState<AIGeneratedPlan[]>([]);
  const [expandedPlanId, setExpandedPlanId] = useState<string | null>(null);

  useEffect(() => {
    setSavedPlans(getSavedPlans());
  }, []);

  const handlePlanSaved = (plan: AIGeneratedPlan) => {
    setSavedPlans(getSavedPlans());
    setExpandedPlanId(plan.id);
    setActiveTab('ai');
  };

  const handleDeletePlan = (id: string) => {
    deletePlan(id);
    setSavedPlans(getSavedPlans());
    if (expandedPlanId === id) setExpandedPlanId(null);
  };

  const dayOfWeek = new Date().getDay();

  const joinDate: Date = userProfile?.joinDate
    ? (userProfile.joinDate instanceof Date
        ? userProfile.joinDate
        : new Date((userProfile.joinDate as any).toDate?.() ?? userProfile.joinDate))
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

  const handleRecorded = (id: string) => {
    if (selectedRound === 1) setR1Done(prev => new Set(prev).add(id));
    else setR2Done(prev => new Set(prev).add(id));
    setSelected(null);
  };

  const renderRound = (round: 1 | 2) => {
    const done = round === 1 ? r1Done : r2Done;
    const isActive = round === 1 ? isMorning : !isMorning;
    const isLocked = round === 2 && isMorning;

    return (
      <div key={`round${round}`}>
        <div className="flex items-center justify-between mb-3">
          <div className="flex flex-col gap-0.5">
            <div className="flex items-center gap-2">
              <span className="font-black text-base" style={{ color: isActive ? '#3C3C3C' : '#AFAFAF' }}>
                {round === 1 ? '☀️ 午前の部' : '🌙 午後の部'}
              </span>
              {isActive && !isLocked && (
                <span className="text-xs font-extrabold px-2 py-0.5 rounded-full" style={{ background: '#D7FFB8', color: '#46A302' }}>
                  NOW
                </span>
              )}
            </div>
            <span className="text-xs font-bold text-duo-gray">
              {round === 1 ? '0:00 〜 12:00' : '12:00 〜 24:00'}
            </span>
          </div>
          <span className="font-extrabold text-sm" style={{ color: isLocked ? '#AFAFAF' : '#58CC02' }}>
            {done.size}/{todayExercises.length}
          </span>
        </div>

        {isLocked ? (
          <div className="rounded-2xl py-5 text-center" style={{ background: '#F7F7F7', border: '2px dashed #e5e5e5' }}>
            <p className="text-3xl mb-2">🌙</p>
            <p className="text-duo-gray font-bold text-sm">12:00から開始</p>
            <p className="text-duo-gray font-bold text-xs mt-1">午前できなくても午後にまとめてOK！</p>
          </div>
        ) : (
          <>
            <div className="space-y-2">
              {todayExercises.map(ex => {
                const isDone = done.has(ex.id);
                const diff = DIFFICULTY_COLOR[ex.difficulty];
                return (
                  <button
                    key={ex.id}
                    onClick={() => { setSelected(ex); setSelectedRound(round); }}
                    className="w-full flex items-center gap-3 rounded-2xl p-3 transition-all text-left active:scale-98"
                    style={{
                      background: isDone ? 'rgba(88,204,2,0.06)' : '#F7F7F7',
                      border: `2px solid ${isDone ? 'rgba(88,204,2,0.25)' : '#e5e5e5'}`,
                    }}
                  >
                    <div className="w-11 h-11 rounded-xl flex items-center justify-center text-2xl shrink-0"
                      style={{ background: isDone ? 'rgba(88,204,2,0.15)' : 'white', border: '1.5px solid #e5e5e5' }}>
                      {ex.emoji}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="font-extrabold text-sm"
                          style={{ color: isDone ? '#AFAFAF' : '#3C3C3C', textDecoration: isDone ? 'line-through' : 'none' }}>
                          {ex.name}
                        </p>
                        <span className="text-xs font-extrabold px-1.5 py-0.5 rounded-full shrink-0"
                          style={{ background: diff.bg, color: diff.text }}>
                          {ex.difficulty}
                        </span>
                      </div>
                      <p className="text-duo-gray font-bold text-xs">{ex.reps}</p>
                    </div>
                    <div className="shrink-0">
                      {isDone
                        ? <span className="text-xl" style={{ color: '#58CC02' }}>✅</span>
                        : <span className="text-duo-gray font-bold text-xs">›</span>
                      }
                    </div>
                  </button>
                );
              })}
            </div>
            {done.size === todayExercises.length && todayExercises.length > 0 && (
              <div className="mt-3 py-3 rounded-2xl text-center font-black text-sm"
                style={{ background: 'rgba(88,204,2,0.08)', color: '#46A302' }}>
                🎉 Round {round} 完了！すごい！
              </div>
            )}
          </>
        )}
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-4">

        {/* ── タブ切替 ──────────────────────────────────────────────────── */}
        <div className="flex gap-2">
          {(['standard', 'ai'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className="flex-1 rounded-2xl py-2.5 font-extrabold text-sm transition-all"
              style={{
                background: activeTab === tab ? '#58CC02' : 'white',
                color: activeTab === tab ? 'white' : '#4b4b4b',
                border: `2px solid ${activeTab === tab ? '#46A302' : '#e5e5e5'}`,
                boxShadow: activeTab === tab ? '0 3px 0 #46A302' : 'none',
              }}
            >
              {tab === 'standard' ? '📋 標準プラン' : '🤖 AIプラン'}
              {tab === 'ai' && savedPlans.length > 0 && (
                <span
                  className="ml-1.5 inline-flex items-center justify-center w-5 h-5 rounded-full text-[10px] font-black"
                  style={{ background: activeTab === 'ai' ? 'rgba(255,255,255,0.3)' : '#58CC02', color: 'white' }}
                >
                  {savedPlans.length}
                </span>
              )}
            </button>
          ))}
        </div>

        {/* ── AIプランタブ ─────────────────────────────────────────────── */}
        {activeTab === 'ai' && (
          <div className="space-y-4">
            {/* 作成ボタン */}
            <button
              onClick={() => setShowCreateModal(true)}
              className="duo-btn-primary w-full py-4 text-base flex items-center justify-center gap-2"
            >
              <span className="text-xl">🤖</span>
              <span>新しいプランをAIで作成</span>
            </button>

            {/* 保存済みプラン一覧 */}
            {savedPlans.length === 0 ? (
              <div
                className="rounded-2xl p-8 text-center"
                style={{ background: 'white', border: '2px dashed #e5e5e5' }}
              >
                <div className="text-5xl mb-3">🤖</div>
                <p className="font-black text-duo-dark text-lg mb-1">まだプランがありません</p>
                <p className="text-duo-gray font-bold text-sm">
                  上のボタンから目標を入力して、<br/>AIにあなた専用プランを作ってもらいましょう！
                </p>
              </div>
            ) : (
              savedPlans.map(plan => {
                const isOpen = expandedPlanId === plan.id;
                return (
                  <div key={plan.id} className="duo-card overflow-hidden">
                    {/* プランヘッダー */}
                    <button
                      onClick={() => setExpandedPlanId(isOpen ? null : plan.id)}
                      className="w-full text-left px-5 py-4 flex items-start gap-3 hover:bg-gray-50 transition-colors"
                    >
                      <div
                        className="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
                        style={{ background: '#D7FFB8' }}
                      >
                        🤖
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="font-black text-duo-dark text-base leading-tight truncate">{plan.title}</p>
                        <p className="text-duo-gray font-bold text-xs truncate mt-0.5">{plan.goal}</p>
                        <div className="flex flex-wrap gap-1.5 mt-1.5">
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#E8F5E9', color: '#46A302' }}>
                            週{plan.daysPerWeek}日
                          </span>
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#E3F2FD', color: '#0a6c96' }}>
                            {PROVIDER_LABELS[plan.provider].split(' ')[0]}
                          </span>
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#F7F7F7', color: '#9e9e9e' }}>
                            {new Date(plan.createdAt).toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' })}
                          </span>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <button
                          onClick={e => { e.stopPropagation(); handleDeletePlan(plan.id); }}
                          className="text-duo-gray hover:text-red-500 text-sm p-1.5 rounded-lg hover:bg-red-50 transition-colors"
                          title="削除"
                        >
                          🗑
                        </button>
                        <span className="text-duo-gray text-sm">{isOpen ? '▲' : '▼'}</span>
                      </div>
                    </button>

                    {/* 展開時：プラン詳細 */}
                    {isOpen && (
                      <div className="border-t border-gray-100 px-4 pb-4 pt-3 space-y-3">
                        {/* サマリー */}
                        <p className="text-duo-dark font-bold text-sm leading-relaxed">{plan.summary}</p>

                        {/* スケジュール（折りたたみ） */}
                        <div>
                          <p className="font-extrabold text-duo-dark text-xs uppercase tracking-wider mb-2">📅 週間スケジュール</p>
                          <div className="space-y-1.5">
                            {plan.weeklySchedule.map((day, i) => (
                              <div
                                key={i}
                                className="rounded-xl px-3 py-2.5"
                                style={{ background: '#F7F7F7', border: '1.5px solid #e5e5e5' }}
                              >
                                <div className="flex items-center justify-between mb-1">
                                  <p className="font-extrabold text-duo-dark text-sm">{day.day}</p>
                                  <div className="flex gap-1.5">
                                    {day.estimatedTime && (
                                      <span className="text-[10px] font-bold text-duo-gray">⏱ {day.estimatedTime}</span>
                                    )}
                                  </div>
                                </div>
                                <p className="text-duo-gray font-bold text-xs mb-1.5">{day.focus}</p>
                                <div className="flex flex-wrap gap-1">
                                  {day.exercises.map((ex, j) => (
                                    <span
                                      key={j}
                                      className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                                      style={{ background: '#E8F5E9', color: '#2d7a00' }}
                                    >
                                      {ex.name} {ex.reps}×{ex.sets}
                                    </span>
                                  ))}
                                  {day.cardio && (
                                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#E3F2FD', color: '#0a6c96' }}>
                                      🏃 {day.cardio}
                                    </span>
                                  )}
                                </div>
                              </div>
                            ))}
                          </div>
                        </div>

                        {/* 栄養 + マイルストーン（横2列） */}
                        {(plan.nutritionTips.length > 0 || plan.progressMilestones.length > 0) && (
                          <div className="grid grid-cols-2 gap-3">
                            {plan.nutritionTips.length > 0 && (
                              <div className="rounded-xl p-3" style={{ background: '#E8F5E9', border: '1.5px solid #58CC02' }}>
                                <p className="font-extrabold text-xs mb-1.5" style={{ color: '#2d7a00' }}>🥗 栄養</p>
                                {plan.nutritionTips.slice(0, 2).map((tip, i) => (
                                  <p key={i} className="text-[11px] font-bold leading-tight mb-1" style={{ color: '#2d7a00' }}>• {tip}</p>
                                ))}
                              </div>
                            )}
                            {plan.progressMilestones.length > 0 && (
                              <div className="rounded-xl p-3" style={{ background: '#FFF3E0', border: '1.5px solid #FF9600' }}>
                                <p className="font-extrabold text-xs mb-1.5" style={{ color: '#8a4700' }}>🏆 目標</p>
                                {plan.progressMilestones.slice(0, 2).map((m, i) => (
                                  <p key={i} className="text-[11px] font-bold leading-tight mb-1" style={{ color: '#8a4700' }}>
                                    {m.week}週: {m.milestone}
                                  </p>
                                ))}
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              })
            )}
          </div>
        )}

        {/* ── 標準プランタブ ──────────────────────────────────────────── */}
        {activeTab === 'standard' && <>

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
              <p className="font-black text-duo-dark">{todayCardio.type} {todayCardio.detail}</p>
            </div>
          </div>
        )}

        {/* 午前スキップ通知 */}
        {!isMorning && r1Done.size === 0 && (
          <div
            className="duo-card p-4 flex items-center gap-3"
            style={{ background: 'linear-gradient(135deg, #FFF8E1, #FFF3E0)', border: '2px solid rgba(255,150,0,0.3)' }}
          >
            <span className="text-2xl">💡</span>
            <div>
              <p className="font-extrabold text-duo-dark text-sm">午前の部を飛ばした？まとめてやろう！</p>
              <p className="text-duo-gray font-bold text-xs mt-0.5">午前・午後の2周を今やってもOK！</p>
            </div>
          </div>
        )}

        {/* 筋トレカード（午前・午後2ラウンド） */}
        <div className="duo-card p-5">
          <div className="flex items-center justify-between mb-1">
            <h2 className="font-black text-duo-dark text-lg">
              {phase === 1 ? '💥 15分サーキット' : '💪 分割トレーニング'}
            </h2>
            <span className="font-extrabold text-sm" style={{ color: '#58CC02' }}>
              {r1Done.size + r2Done.size}/{todayExercises.length * 2}
            </span>
          </div>
          {phase === 1 && (
            <p className="text-xs font-extrabold mb-4" style={{ color: '#FF9600' }}>
              午前・午後に1周ずつ ／ タップで詳細・記録
            </p>
          )}

          {renderRound(1)}

          <div className="my-4" style={{ borderTop: '1.5px dashed #e5e5e5' }} />

          {renderRound(2)}
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
              <div key={label} className="rounded-2xl p-3 flex flex-col items-center text-center" style={{ background: bg }}>
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
            ].map(tip => (
              <p key={tip} className="text-xs font-bold text-duo-gray">{tip}</p>
            ))}
          </div>
        </div>

        </> /* 標準プランタブ閉じ */}

      </div>{/* max-w-2xl 閉じ */}

      {/* Detail sheet */}
      {selected && (
        <DetailSheet
          exercise={selected}
          onClose={() => setSelected(null)}
          onRecorded={handleRecorded}
        />
      )}

      {/* AI プラン作成モーダル */}
      {showCreateModal && (
        <CreatePlanModal
          onClose={() => setShowCreateModal(false)}
          onSaved={handlePlanSaved}
        />
      )}
    </div>
  );
};
