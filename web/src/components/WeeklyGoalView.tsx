import React, { useEffect, useState } from 'react';
import {
  getWeeklySetProgress,
  getWeeklySetLog,
  getDailySetGoal,
  saveDailySetGoal,
  getWeekLabel,
  getActiveDaysElapsed,
  type WeeklySetProgress,
  type CompletedSetRecord,
} from '../services/firebase';
import { useAppStore } from '../store/appStore';

const EXERCISE_EMOJI: Record<string, string> = {
  pushup: '💪', 'push-up': '💪',
  squat: '🏋️',
  situp: '🔥', 'sit-up': '🔥',
  lunge: '🦵',
  burpee: '⚡',
  plank: '🧘',
};
function emoji(id: string) {
  return EXERCISE_EMOJI[id.toLowerCase()] ?? '🏃';
}

const EX_COLORS = [
  { bg: '#D7FFB8', border: '#58CC02', text: '#2d7a00' },
  { bg: '#E3F2FD', border: '#1CB0F6', text: '#0a6c96' },
  { bg: '#FFF3E0', border: '#FF9600', text: '#8a4700' },
  { bg: '#F3E5F5', border: '#CE82FF', text: '#6a1b9a' },
  { bg: '#FCE4EC', border: '#FF4B4B', text: '#7f0000' },
];

const ACTIVE_DAYS = 5;

const DAY_NAMES = ['日', '月', '火', '水', '木', '金', '土'];

function formatSetDate(d: Date): string {
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const dow = DAY_NAMES[d.getDay()];
  return `${m}/${day}（${dow}）`;
}
function formatSetTime(d: Date): string {
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}
function isToday(d: Date): boolean {
  const now = new Date();
  return d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate();
}

export const WeeklyGoalView: React.FC = () => {
  const user = useAppStore((s) => s.user);

  const [progress, setProgress] = useState<WeeklySetProgress>({ completedSets: 0, exercises: {} });
  const [setLog, setSetLog] = useState<CompletedSetRecord[]>([]);
  const [dailySets, setDailySets] = useState(2);
  const [draftDailySets, setDraftDailySets] = useState(2);
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  function toggleExpand(id: string) {
    setExpandedIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [p, log, d] = await Promise.all([
        getWeeklySetProgress(user.uid),
        getWeeklySetLog(user.uid),
        getDailySetGoal(user.uid),
      ]);
      setProgress(p);
      setSetLog(log);
      setDailySets(d);
      setDraftDailySets(d);
      setIsLoading(false);
    })();
  }, [user]);

  // 今日のセット数
  const todayCount = setLog.filter(r => isToday(r.timestamp)).length;

  const weeklyTarget = dailySets * ACTIVE_DAYS;
  const activeDays = getActiveDaysElapsed();
  const expectedNow = dailySets * activeDays;
  const pct = expectedNow > 0 ? Math.min((progress.completedSets / expectedNow) * 100, 100) : 0;
  const weekPct = weeklyTarget > 0 ? Math.min((progress.completedSets / weeklyTarget) * 100, 100) : 0;
  const isOnTrack = pct >= 100;

  const handleSave = async () => {
    if (!user) return;
    setIsSaving(true);
    await saveDailySetGoal(user.uid, draftDailySets);
    setDailySets(draftDailySets);
    setIsSaving(false);
    setIsEditing(false);
  };


  if (isLoading) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <img src="/mascot.png" alt="" className="w-20 h-20 rounded-full object-cover animate-wiggle" />
          <p className="text-duo-green font-extrabold text-lg">読み込み中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-4">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <img src="/mascot.png" alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
            <div>
              <h2 className="text-2xl font-black text-duo-dark">週間目標</h2>
              <p className="text-duo-gray font-bold text-sm">📅 {getWeekLabel()}</p>
            </div>
          </div>
          {!isEditing && (
            <button
              onClick={() => setIsEditing(true)}
              className="duo-btn-secondary px-4 py-2 text-sm"
            >
              ✏️ 編集
            </button>
          )}
        </div>

        {/* Rule hint */}
        <div
          className="rounded-2xl px-4 py-2 flex items-center gap-2"
          style={{ background: '#E3F2FD', border: '1.5px solid #1CB0F6' }}
        >
          <span className="text-lg">💡</span>
          <p className="font-bold text-sm" style={{ color: '#0a6c96' }}>
            1日{dailySets}セット × {ACTIVE_DAYS}日（週{ACTIVE_DAYS}日）＝ 週{weeklyTarget}セット
          </p>
        </div>

        {/* Main progress card */}
        <div
          className="duo-card p-5"
          style={{
            borderColor: isOnTrack ? '#58CC02' : '#FFD900',
            boxShadow: `0 4px 0 ${isOnTrack ? '#46A302' : '#CE9700'}`,
          }}
        >
          <div className="flex items-center justify-between mb-1">
            <p className="font-extrabold text-duo-dark text-base">
              {isOnTrack ? '🎉 ペース通り！' : '🎯 今週のセット進捗'}
            </p>
            <span
              className="text-xs font-extrabold px-3 py-1 rounded-full"
              style={{
                background: isOnTrack ? '#D7FFB8' : '#FFF8E1',
                color: isOnTrack ? '#46A302' : '#CE9700',
              }}
            >
              今日 {todayCount}セット
            </span>
          </div>

          <div className="flex items-end gap-2 mb-3">
            <span
              className="text-5xl font-black leading-none"
              style={{ color: isOnTrack ? '#46A302' : '#CE9700' }}
            >
              {progress.completedSets}
            </span>
            <span className="text-xl font-black text-duo-gray mb-1">/ {weeklyTarget} セット</span>
            <span
              className="ml-auto font-black text-lg"
              style={{ color: isOnTrack ? '#46A302' : '#CE9700' }}
            >
              {Math.round(weekPct)}%
            </span>
          </div>

          <div className="duo-progress-bar" style={{ height: '14px' }}>
            <div
              className="h-full rounded-full transition-all duration-500"
              style={{
                width: `${weekPct}%`,
                background: isOnTrack
                  ? 'linear-gradient(90deg, #58CC02, #91E62A)'
                  : 'linear-gradient(90deg, #FFD900, #FF9600)',
              }}
            />
          </div>

          <p className="text-duo-gray font-bold text-xs mt-2">
            今日まで目標 {expectedNow} セット（{activeDays}日経過）
          </p>
        </div>

        {/* Set timeline */}
        {setLog.length > 0 && (
          <div className="duo-card p-5 space-y-3">
            <p className="text-duo-dark font-extrabold text-sm uppercase tracking-wider">
              今週のセット一覧（{setLog.length}件）
            </p>
            {setLog.map((record, idx) => {
              const isExp = expandedIds.has(record.id);
              const today = isToday(record.timestamp);
              return (
                <div key={record.id}>
                  {/* 日付区切り（前と日付が変わったとき） */}
                  {(idx === 0 || formatSetDate(setLog[idx - 1].timestamp) !== formatSetDate(record.timestamp)) && (
                    <p className="text-duo-gray font-extrabold text-xs mb-1 mt-2 first:mt-0">
                      {today ? '🟢 今日' : formatSetDate(record.timestamp)}
                    </p>
                  )}

                  {/* セット行 */}
                  <button
                    onClick={() => toggleExpand(record.id)}
                    className="w-full text-left rounded-2xl px-4 py-3 flex items-center gap-3 transition-colors"
                    style={{
                      background: today ? '#E8F5E9' : '#F7F7F7',
                      border: `2px solid ${today ? '#58CC02' : '#e5e5e5'}`,
                    }}
                  >
                    {/* 時刻 */}
                    <div className="shrink-0 text-center" style={{ minWidth: '3rem' }}>
                      <p
                        className="font-black text-base leading-none"
                        style={{ color: today ? '#46A302' : '#4b4b4b' }}
                      >
                        {formatSetTime(record.timestamp)}
                      </p>
                      {!today && (
                        <p className="text-duo-gray font-bold text-[10px] leading-none mt-0.5">
                          {formatSetDate(record.timestamp).replace(/（.）/, '')}
                        </p>
                      )}
                    </div>

                    {/* 内容サマリー */}
                    <div className="flex-1 min-w-0">
                      <p className="font-extrabold text-duo-dark text-sm truncate">
                        {record.exercises.map(e => `${emoji(e.exerciseId)}${e.exerciseName}`).join('・')}
                      </p>
                      <p className="font-bold text-duo-gray text-xs">
                        {record.totalReps} rep · +{record.totalXP} XP
                      </p>
                    </div>

                    {/* 展開アイコン */}
                    <span className="text-duo-gray text-sm shrink-0">{isExp ? '▲' : '▼'}</span>
                  </button>

                  {/* 詳細展開 */}
                  {isExp && (
                    <div className="mt-1 ml-4 space-y-1 pl-3 border-l-2 border-duo-green">
                      {record.exercises.map((ex, i) => {
                        const col = EX_COLORS[i % EX_COLORS.length];
                        return (
                          <div
                            key={i}
                            className="flex items-center gap-3 rounded-xl px-3 py-2"
                            style={{ background: col.bg, border: `1.5px solid ${col.border}` }}
                          >
                            <span className="text-xl shrink-0">{emoji(ex.exerciseId)}</span>
                            <div className="flex-1 min-w-0">
                              <p className="font-extrabold text-duo-dark text-sm">{ex.exerciseName}</p>
                              <p className="font-bold text-xs" style={{ color: col.text }}>
                                {ex.reps} rep · +{ex.points} XP
                              </p>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* Edit mode */}
        {isEditing && (
          <div className="duo-card p-5 space-y-4">
            <p className="text-duo-dark font-extrabold text-sm uppercase tracking-wider">
              1日のセット数を設定
            </p>
            <div
              className="rounded-2xl p-5 text-center"
              style={{ background: '#D7FFB8', border: '2px solid #58CC02' }}
            >
              <p className="text-duo-green font-extrabold text-xs uppercase tracking-widest mb-3">
                1日のセット数
              </p>
              <div className="flex items-center justify-center gap-6">
                <button
                  onClick={() => setDraftDailySets(v => Math.max(1, v - 1))}
                  className="w-12 h-12 rounded-2xl font-black text-2xl flex items-center justify-center"
                  style={{ background: 'white', border: '2px solid #58CC02', color: '#46A302', boxShadow: '0 3px 0 #46A302' }}
                >
                  −
                </button>
                <span className="text-6xl font-black" style={{ color: '#2d7a00' }}>{draftDailySets}</span>
                <button
                  onClick={() => setDraftDailySets(v => v + 1)}
                  className="w-12 h-12 rounded-2xl font-black text-2xl flex items-center justify-center"
                  style={{ background: '#58CC02', color: 'white', boxShadow: '0 3px 0 #46A302' }}
                >
                  ＋
                </button>
              </div>
              <p className="text-duo-green font-bold text-sm mt-3">
                週間目標 = {draftDailySets} × {ACTIVE_DAYS}日 = <span className="font-black">{draftDailySets * ACTIVE_DAYS} セット</span>
              </p>
            </div>

            <div className="flex gap-3 pt-1">
              <button
                onClick={() => { setDraftDailySets(dailySets); setIsEditing(false); }}
                className="duo-btn-secondary flex-1 text-base py-3"
              >
                キャンセル
              </button>
              <button
                onClick={handleSave}
                disabled={isSaving}
                className="duo-btn-primary flex-1 text-base py-3"
              >
                {isSaving ? '保存中...' : '保存'}
              </button>
            </div>
          </div>
        )}

        {/* Empty state CTA */}
        {progress.completedSets === 0 && !isEditing && (
          <div
            className="rounded-2xl px-5 py-4 flex items-center gap-3"
            style={{ background: '#FFF8E1', border: '2px solid #FFD900' }}
          >
            <span className="text-2xl">🏁</span>
            <p className="font-bold text-sm" style={{ color: '#8a5700' }}>
              まだ今週のセットがありません。ホームからトレーニングを始めよう！
            </p>
          </div>
        )}

      </div>
    </div>
  );
};
