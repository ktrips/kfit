import React, { useEffect, useState } from 'react';
import { useAppStore } from '../../store/appStore';
import {
  TimeSlot,
  DailyTimeSlotSettings,
  DailyTimeSlotProgress,
  TIME_SLOT_INFO,
  calculateCompletionRate
} from '../../types/timeSlot';
import {
  getTodaySettings,
  getTodayProgress,
  subscribeTodayProgress,
  recordMindfulnessCompleted,
  recordStretchCompleted,
  toggleCustomActivity
} from '../../services/timeSlotService';
import TimeSlotCard from './TimeSlotCard';
import TimeSlotEditModal from './TimeSlotEditModal';

// Good Job! 演出の称賛メッセージ（ランダム表示）
const PRAISE_LINES = [
  'その調子！継続は力なり💪',
  '小さな一歩が大きな変化に！',
  '今日もえらい！明日も会おうね',
  'できたね！この積み重ねが実績になる',
  'ナイス！やる気が続く人はこうやって作られる',
  '完璧！今日のあなたは昨日より強い',
];

const TimeSlotGoals: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [settings, setSettings] = useState<DailyTimeSlotSettings | null>(null);
  const [progress, setProgress] = useState<DailyTimeSlotProgress | null>(null);
  const [loading, setLoading] = useState(true);
  const [editingSlot, setEditingSlot] = useState<TimeSlot | null>(null);
  // Good Job! 演出（禁酒・勉強・語学などのタスク完了時）
  const [celebration, setCelebration] = useState<{ emoji: string; title: string; praise: string } | null>(null);

  const showCelebration = (emoji: string, title: string) => {
    setCelebration({
      emoji,
      title,
      praise: PRAISE_LINES[Math.floor(Math.random() * PRAISE_LINES.length)],
    });
    window.setTimeout(() => setCelebration(null), 2400);
  };

  useEffect(() => {
    loadData();
    if (!user) return;
    // iOS / Watch での記録をリアルタイム反映
    const unsubscribe = subscribeTodayProgress(user.uid, setProgress);
    return unsubscribe;
  }, [user]);

  const loadData = async () => {
    if (!user) return;

    setLoading(true);
    try {
      const [settingsData, progressData] = await Promise.all([
        getTodaySettings(user.uid),
        getTodayProgress(user.uid)
      ]);
      setSettings(settingsData);
      setProgress(progressData);
    } catch (error) {
      console.error('Failed to load time slot data:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  if (!settings || !progress) {
    return <div>データの読み込みに失敗しました</div>;
  }

  return (
    <div className="max-w-4xl mx-auto p-4 space-y-6">
      {/* Header */}
      <div className="duo-card p-6">
        <div className="flex items-center space-x-4">
          <div className="flex-shrink-0">
            <div className="w-14 h-14 bg-gradient-to-br from-green-400 to-green-600 rounded-full flex items-center justify-center">
              <span className="text-2xl">🕐</span>
            </div>
          </div>
          <div>
            <h1 className="text-2xl font-black text-duo-dark">
              時間帯別の目標設定
            </h1>
            <p className="text-sm text-duo-gray font-bold">
              1日を5つの時間帯に分けて管理
            </p>
          </div>
        </div>
        <p className="mt-4 text-sm text-duo-gray font-bold">
          夜中・朝・昼・午後・夜ごとに、トレーニング、マインドフルネス、ストレッチ、食事kcal、水分ml、カスタム活動を設定できます。
        </p>
        <div className="grid grid-cols-5 gap-2 mt-4">
          {Object.values(TimeSlot).map(slot => {
            const goal = settings.goals.find(g => g.timeSlot === slot);
            const prog = progress.progress.find(p => p.timeSlot === slot);
            const pct = goal && prog ? Math.round(calculateCompletionRate(prog, goal) * 100) : 0;
            return (
              <div key={slot} className="rounded-xl bg-duo-gray-light p-2 text-center">
                <div className="text-lg">{TIME_SLOT_INFO[slot].emoji}</div>
                <div className="text-[10px] font-black text-duo-dark">{TIME_SLOT_INFO[slot].displayName}</div>
                <div className="text-xs font-black text-duo-green">{pct}%</div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Time Slot Cards */}
      <div className="space-y-4">
        {Object.values(TimeSlot).map(slot => {
          const goal = settings.goals.find(g => g.timeSlot === slot);
          const prog = progress.progress.find(p => p.timeSlot === slot);

          if (!goal || !prog) return null;

          return (
            <TimeSlotCard
              key={slot}
              timeSlot={slot}
              goal={goal}
              progress={prog}
              onEdit={() => setEditingSlot(slot)}
              onAddMindfulness={async () => {
                if (!user) return;
                await recordMindfulnessCompleted(user.uid, slot);
                await loadData();
              }}
              onAddStretch={async () => {
                if (!user) return;
                await recordStretchCompleted(user.uid, slot, 1);
                await loadData();
              }}
              onToggleCustomActivity={async (activityId) => {
                if (!user) return;
                // 未完了 → 完了 への遷移なら Good Job! 演出を出す
                const wasCompleted = (prog.completedActivityIds || []).includes(activityId);
                await toggleCustomActivity(user.uid, slot, activityId);
                await loadData();
                if (!wasCompleted) {
                  const activity = goal.customActivities?.find(a => a.id === activityId);
                  showCelebration(activity?.emoji ?? '🎯', activity?.title ?? '今日の目標');
                }
              }}
            />
          );
        })}
      </div>

      {/* Edit Modal */}
      {editingSlot && (
        <TimeSlotEditModal
          timeSlot={editingSlot}
          onClose={() => {
            setEditingSlot(null);
            loadData();
          }}
        />
      )}

      {/* Good Job! 演出（タスク完了時） */}
      {celebration && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center"
          style={{ background: 'rgba(0,0,0,0.35)' }}
          onClick={() => setCelebration(null)}
        >
          <div
            className="bg-white rounded-3xl px-8 py-7 mx-10 text-center"
            style={{ boxShadow: '0 12px 40px rgba(88,204,2,0.35)', animation: 'goodjob-pop 0.35s ease-out' }}
          >
            <img
              src="/mascot.png"
              alt="Fitingo"
              style={{ width: 96, height: 96, borderRadius: '50%', objectFit: 'cover', margin: '0 auto' }}
            />
            <p className="mt-3 text-3xl font-black" style={{ color: '#58CC02' }}>Good Job!</p>
            <p className="mt-2 text-lg font-black text-duo-dark">
              {celebration.emoji} {celebration.title} 完了！
            </p>
            <p className="mt-2 text-sm font-bold" style={{ color: '#999' }}>
              {celebration.praise}
            </p>
          </div>
          <style>{`
            @keyframes goodjob-pop {
              0% { transform: scale(0.7); opacity: 0; }
              100% { transform: scale(1); opacity: 1; }
            }
          `}</style>
        </div>
      )}
    </div>
  );
};

export default TimeSlotGoals;
