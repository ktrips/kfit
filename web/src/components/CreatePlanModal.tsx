import React, { useState } from 'react';
import {
  generateWorkoutPlan, savePlan, getAISettings,
  type AIGeneratedPlan, type WeekDayPlan,
  PROVIDER_LABELS,
} from '../services/aiService';

// ── 小コンポーネント ─────────────────────────────────────────────────────────

const FITNESS_LEVELS = ['初心者（運動習慣なし）', '初中級（週1〜2回）', '中級（週3〜4回）', '上級（週5回以上）'];

function StepDot({ n, active, done }: { n: number; active: boolean; done: boolean }) {
  return (
    <div
      className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-black shrink-0"
      style={{
        background: done ? '#58CC02' : active ? '#1CB0F6' : '#e5e5e5',
        color: done || active ? 'white' : '#9e9e9e',
      }}
    >
      {done ? '✓' : n}
    </div>
  );
}

// ── 生成されたプランの表示 ────────────────────────────────────────────────────

function PlanDisplay({ plan }: { plan: AIGeneratedPlan }) {
  const [openDay, setOpenDay] = useState<string | null>(null);

  const providerLabel = PROVIDER_LABELS[plan.provider];

  return (
    <div className="space-y-4">
      {/* タイトル + サマリー */}
      <div
        className="rounded-2xl p-4"
        style={{ background: 'linear-gradient(135deg, #D7FFB8 0%, #E8F5E9 100%)', border: '2px solid #58CC02' }}
      >
        <div className="flex items-start justify-between gap-2 mb-2">
          <h3 className="font-black text-duo-dark text-lg leading-tight">{plan.title}</h3>
          <span
            className="text-[10px] font-extrabold px-2 py-0.5 rounded-full shrink-0"
            style={{ background: '#58CC02', color: 'white' }}
          >
            {providerLabel.split(' ')[0]}
          </span>
        </div>
        <p className="text-duo-dark font-bold text-sm leading-relaxed">{plan.summary}</p>
        <div className="flex flex-wrap gap-2 mt-3">
          <span className="text-xs font-extrabold px-2.5 py-1 rounded-full" style={{ background: '#E8F5E9', color: '#46A302' }}>
            週{plan.daysPerWeek}日
          </span>
          <span className="text-xs font-extrabold px-2.5 py-1 rounded-full" style={{ background: '#E3F2FD', color: '#0a6c96' }}>
            期限: {plan.deadline}
          </span>
          <span className="text-xs font-extrabold px-2.5 py-1 rounded-full" style={{ background: '#FFF3E0', color: '#8a4700' }}>
            {plan.fitnessLevel.split('（')[0]}
          </span>
        </div>
      </div>

      {/* 週間スケジュール */}
      <div className="duo-card overflow-hidden">
        <div className="px-4 pt-4 pb-2">
          <p className="font-extrabold text-duo-dark text-sm uppercase tracking-wider">📅 週間スケジュール</p>
        </div>
        {plan.weeklySchedule.map((day: WeekDayPlan) => (
          <div key={day.day} className="border-t border-gray-100">
            <button
              onClick={() => setOpenDay(openDay === day.day ? null : day.day)}
              className="w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-gray-50 transition-colors"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="font-extrabold text-duo-dark text-sm">{day.day}</p>
                  {day.estimatedTime && (
                    <span className="text-[10px] font-bold text-duo-gray">⏱ {day.estimatedTime}</span>
                  )}
                </div>
                <p className="text-duo-gray font-bold text-xs truncate">{day.focus}</p>
              </div>
              <span className="text-duo-gray text-sm shrink-0">{openDay === day.day ? '▲' : '▼'}</span>
            </button>

            {openDay === day.day && (
              <div className="px-4 pb-4 space-y-2">
                {day.exercises.map((ex, i) => (
                  <div
                    key={i}
                    className="rounded-xl p-3 flex gap-3"
                    style={{ background: '#F7F7F7', border: '1.5px solid #e5e5e5' }}
                  >
                    <div
                      className="w-8 h-8 rounded-lg flex items-center justify-center text-white font-black text-xs shrink-0"
                      style={{ background: '#58CC02' }}
                    >
                      {ex.sets}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-extrabold text-duo-dark text-sm">{ex.name}</p>
                      <p className="text-duo-gray font-bold text-xs">
                        {ex.sets}セット × {ex.reps} 休憩 {ex.rest}
                      </p>
                      {ex.tip && (
                        <p className="text-xs font-bold mt-0.5" style={{ color: '#0a6c96' }}>
                          💡 {ex.tip}
                        </p>
                      )}
                    </div>
                  </div>
                ))}
                {day.cardio && (
                  <div
                    className="rounded-xl px-3 py-2 flex items-center gap-2"
                    style={{ background: '#E3F2FD', border: '1.5px solid #1CB0F6' }}
                  >
                    <span className="text-sm">🏃</span>
                    <p className="text-xs font-bold" style={{ color: '#0a6c96' }}>{day.cardio}</p>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* 栄養アドバイス */}
      {plan.nutritionTips.length > 0 && (
        <div className="duo-card p-4">
          <p className="font-extrabold text-duo-dark text-sm uppercase tracking-wider mb-3">🥗 栄養アドバイス</p>
          <ul className="space-y-2">
            {plan.nutritionTips.map((tip, i) => (
              <li key={i} className="flex items-start gap-2">
                <span
                  className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-black shrink-0 mt-0.5"
                  style={{ background: '#58CC02', color: 'white' }}
                >
                  {i + 1}
                </span>
                <p className="text-duo-dark font-bold text-sm">{tip}</p>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* マイルストーン */}
      {plan.progressMilestones.length > 0 && (
        <div className="duo-card p-4">
          <p className="font-extrabold text-duo-dark text-sm uppercase tracking-wider mb-3">🏆 進捗マイルストーン</p>
          <div className="space-y-2">
            {plan.progressMilestones.map((m, i) => (
              <div key={i} className="flex items-center gap-3">
                <div
                  className="shrink-0 text-center rounded-xl px-2 py-1"
                  style={{ background: '#FFF3E0', border: '1.5px solid #FF9600', minWidth: '3.5rem' }}
                >
                  <p className="text-xs font-black" style={{ color: '#8a4700' }}>{m.week}週目</p>
                </div>
                <p className="text-duo-dark font-bold text-sm">{m.milestone}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* 休息日 */}
      {plan.restDays && (
        <div
          className="rounded-2xl px-4 py-3 flex items-start gap-2"
          style={{ background: '#F3E5F5', border: '1.5px solid #CE82FF' }}
        >
          <span className="text-lg">😴</span>
          <div>
            <p className="font-extrabold text-sm" style={{ color: '#6a1b9a' }}>休息日</p>
            <p className="font-bold text-xs" style={{ color: '#6a1b9a' }}>{plan.restDays}</p>
          </div>
        </div>
      )}
    </div>
  );
}

// ── メインモーダル ─────────────────────────────────────────────────────────────

interface CreatePlanModalProps {
  onClose: () => void;
  onSaved: (plan: AIGeneratedPlan) => void;
}

export const CreatePlanModal: React.FC<CreatePlanModalProps> = ({ onClose, onSaved }) => {
  const aiSettings = getAISettings();

  const [step, setStep] = useState<'form' | 'generating' | 'result' | 'no-key'>(!aiSettings ? 'no-key' : 'form');
  const [goal, setGoal] = useState('');
  const [daysPerWeek, setDaysPerWeek] = useState(3);
  const [deadline, setDeadline] = useState('');
  const [fitnessLevel, setFitnessLevel] = useState(FITNESS_LEVELS[0]);
  const [generatedPlan, setGeneratedPlan] = useState<AIGeneratedPlan | null>(null);
  const [error, setError] = useState('');

  // 最短3ヶ月後をデフォルトに
  const minDate = new Date();
  minDate.setMonth(minDate.getMonth() + 1);
  const defaultDeadline = new Date();
  defaultDeadline.setMonth(defaultDeadline.getMonth() + 3);

  const handleGenerate = async () => {
    if (!aiSettings || !goal.trim()) return;
    setStep('generating');
    setError('');
    const dl = deadline || `${defaultDeadline.getFullYear()}年${defaultDeadline.getMonth() + 1}月`;
    try {
      const plan = await generateWorkoutPlan(aiSettings, goal.trim(), daysPerWeek, dl, fitnessLevel);
      setGeneratedPlan(plan);
      setStep('result');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : '生成に失敗しました');
      setStep('form');
    }
  };

  const handleSave = () => {
    if (!generatedPlan) return;
    savePlan(generatedPlan);
    onSaved(generatedPlan);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 sm:p-6"
      style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div
        className="w-full max-w-lg rounded-3xl overflow-hidden flex flex-col"
        style={{
          background: 'white',
          maxHeight: '92vh',
          boxShadow: '0 20px 60px rgba(0,0,0,0.25)',
        }}
      >
        {/* ヘッダー */}
        <div
          className="px-5 py-4 flex items-center justify-between shrink-0"
          style={{ background: 'linear-gradient(135deg, #58CC02 0%, #2d7a00 100%)' }}
        >
          <div className="flex items-center gap-3">
            <span className="text-2xl">🤖</span>
            <div>
              <p className="font-black text-white text-base leading-tight">AIプランを生成</p>
              {aiSettings && (
                <p className="text-white/80 font-bold text-xs">
                  {PROVIDER_LABELS[aiSettings.provider]}
                </p>
              )}
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-white/80 hover:text-white text-2xl font-black leading-none"
          >
            ×
          </button>
        </div>

        {/* コンテンツ */}
        <div className="overflow-y-auto flex-1 p-5">

          {/* API キー未設定 */}
          {step === 'no-key' && (
            <div className="space-y-4 py-4">
              <div className="text-center">
                <div className="text-6xl mb-4">🔑</div>
                <p className="font-black text-duo-dark text-xl mb-2">APIキーが必要です</p>
                <p className="text-duo-gray font-bold text-sm">
                  AI機能を使うには、設定画面でAPIキーを登録してください。
                </p>
              </div>
              <div
                className="rounded-2xl p-4 space-y-2"
                style={{ background: '#E3F2FD', border: '2px solid #1CB0F6' }}
              >
                <p className="font-extrabold text-sm" style={{ color: '#0a6c96' }}>対応プロバイダー</p>
                {(['openai', 'gemini', 'anthropic'] as const).map(p => (
                  <div key={p} className="flex items-center gap-2">
                    <span className="text-lg">
                      {p === 'openai' ? '🟢' : p === 'gemini' ? '🔵' : '🟣'}
                    </span>
                    <p className="font-bold text-sm" style={{ color: '#0a6c96' }}>
                      {PROVIDER_LABELS[p]}
                    </p>
                  </div>
                ))}
              </div>
              <button onClick={onClose} className="duo-btn-primary w-full py-3">
                設定画面へ
              </button>
            </div>
          )}

          {/* 入力フォーム */}
          {step === 'form' && (
            <div className="space-y-5">
              {/* ステップ表示 */}
              <div className="flex items-center gap-2">
                <StepDot n={1} active done={false} />
                <div className="h-0.5 flex-1" style={{ background: '#e5e5e5' }} />
                <StepDot n={2} active={false} done={false} />
                <div className="h-0.5 flex-1" style={{ background: '#e5e5e5' }} />
                <StepDot n={3} active={false} done={false} />
              </div>

              {/* 目標 */}
              <div>
                <label className="font-extrabold text-duo-dark text-sm block mb-2">
                  🎯 達成したい目標
                  <span className="text-duo-green ml-1 text-xs">（必須）</span>
                </label>
                <textarea
                  value={goal}
                  onChange={e => setGoal(e.target.value)}
                  rows={3}
                  placeholder="例：体重を5kg落としてスリムになりたい&#10;例：腹筋を6パックにしたい&#10;例：フルマラソンを完走できる体力をつけたい"
                  className="w-full rounded-2xl border-2 border-gray-200 px-4 py-3 text-sm font-bold text-duo-dark resize-none focus:outline-none focus:border-duo-green"
                />
              </div>

              {/* 週の頻度 */}
              <div>
                <label className="font-extrabold text-duo-dark text-sm block mb-3">
                  📅 週に何日やりたいか
                  <span
                    className="ml-2 font-black px-2.5 py-0.5 rounded-full text-white text-sm"
                    style={{ background: '#58CC02' }}
                  >
                    {daysPerWeek}日
                  </span>
                </label>
                <div className="flex gap-2">
                  {[1, 2, 3, 4, 5, 6, 7].map(d => (
                    <button
                      key={d}
                      onClick={() => setDaysPerWeek(d)}
                      className="flex-1 py-2 rounded-xl font-extrabold text-sm transition-all"
                      style={{
                        background: daysPerWeek === d ? '#58CC02' : '#F7F7F7',
                        color: daysPerWeek === d ? 'white' : '#4b4b4b',
                        border: `2px solid ${daysPerWeek === d ? '#46A302' : '#e5e5e5'}`,
                        boxShadow: daysPerWeek === d ? '0 2px 0 #46A302' : 'none',
                      }}
                    >
                      {d}
                    </button>
                  ))}
                </div>
                <p className="text-duo-gray font-bold text-xs mt-2">
                  {daysPerWeek <= 2 ? '⭐ 週2日：継続しやすい入門コース'
                    : daysPerWeek <= 4 ? '🔥 週3〜4日：バランスのとれた標準コース'
                    : '💪 週5日以上：集中的に鍛えたい上級者向け'}
                </p>
              </div>

              {/* 達成期限 */}
              <div>
                <label className="font-extrabold text-duo-dark text-sm block mb-2">
                  ⏰ いつまでに達成したいか
                </label>
                <input
                  type="month"
                  value={deadline}
                  onChange={e => setDeadline(e.target.value)}
                  min={`${minDate.getFullYear()}-${String(minDate.getMonth() + 1).padStart(2, '0')}`}
                  className="w-full rounded-xl border-2 border-gray-200 px-3 py-2 text-sm font-bold text-duo-dark focus:outline-none focus:border-duo-green"
                />
                {!deadline && (
                  <p className="text-duo-gray font-bold text-xs mt-1">
                    未入力の場合は3ヶ月後を目標として設定します
                  </p>
                )}
              </div>

              {/* 体力レベル */}
              <div>
                <label className="font-extrabold text-duo-dark text-sm block mb-2">💪 現在の体力レベル</label>
                <div className="grid grid-cols-2 gap-2">
                  {FITNESS_LEVELS.map(level => (
                    <button
                      key={level}
                      onClick={() => setFitnessLevel(level)}
                      className="rounded-xl py-2.5 px-3 text-left transition-all"
                      style={{
                        background: fitnessLevel === level ? '#D7FFB8' : '#F7F7F7',
                        border: `2px solid ${fitnessLevel === level ? '#58CC02' : '#e5e5e5'}`,
                      }}
                    >
                      <p className="font-extrabold text-xs leading-tight" style={{ color: fitnessLevel === level ? '#2d7a00' : '#4b4b4b' }}>
                        {level.split('（')[0]}
                      </p>
                      <p className="text-[10px] font-bold leading-none mt-0.5 text-duo-gray">
                        {level.match(/（(.+)）/)?.[1] ?? ''}
                      </p>
                    </button>
                  ))}
                </div>
              </div>

              {/* エラー */}
              {error && (
                <div
                  className="rounded-2xl px-4 py-3 flex items-start gap-2"
                  style={{ background: '#FFE4E4', border: '1.5px solid #FF4B4B' }}
                >
                  <span className="text-sm">❌</span>
                  <p className="font-bold text-sm" style={{ color: '#7f0000' }}>{error}</p>
                </div>
              )}

              {/* 生成ボタン */}
              <button
                onClick={handleGenerate}
                disabled={!goal.trim()}
                className="duo-btn-primary w-full text-lg py-4"
                style={{ opacity: goal.trim() ? 1 : 0.5 }}
              >
                🤖 AIプランを生成する
              </button>
            </div>
          )}

          {/* 生成中 */}
          {step === 'generating' && (
            <div className="py-16 flex flex-col items-center gap-6">
              <div className="relative">
                <div
                  className="w-20 h-20 rounded-full flex items-center justify-center text-4xl animate-pulse"
                  style={{ background: 'linear-gradient(135deg, #D7FFB8, #E8F5E9)' }}
                >
                  🤖
                </div>
                <div
                  className="absolute inset-0 rounded-full border-4 border-t-transparent animate-spin"
                  style={{ borderColor: '#58CC02 transparent transparent transparent' }}
                />
              </div>
              <div className="text-center">
                <p className="font-black text-duo-dark text-xl mb-2">プランを生成中...</p>
                <p className="text-duo-gray font-bold text-sm">AIがあなた専用のプランを作成しています</p>
                <p className="text-duo-gray font-bold text-sm">しばらくお待ちください ✨</p>
              </div>
            </div>
          )}

          {/* 結果表示 */}
          {step === 'result' && generatedPlan && (
            <div className="space-y-4">
              <div
                className="rounded-2xl px-4 py-3 flex items-center gap-2"
                style={{ background: '#D7FFB8', border: '2px solid #58CC02' }}
              >
                <span className="text-xl">🎉</span>
                <p className="font-extrabold text-duo-dark text-sm">プランが完成しました！</p>
              </div>
              <PlanDisplay plan={generatedPlan} />
            </div>
          )}
        </div>

        {/* フッターボタン */}
        {step === 'result' && generatedPlan && (
          <div className="px-5 py-4 border-t border-gray-100 flex gap-3 shrink-0">
            <button
              onClick={() => { setStep('form'); setGeneratedPlan(null); }}
              className="duo-btn-secondary flex-none px-4 py-3 text-sm"
            >
              ↩ 作り直す
            </button>
            <button
              onClick={handleSave}
              className="duo-btn-primary flex-1 py-3 text-base"
            >
              💾 このプランを保存
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
