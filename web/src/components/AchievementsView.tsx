import React, { useEffect, useState } from 'react';
import { getAchievements, ACHIEVEMENT_DEFINITIONS, type Achievement } from '../services/firebase';
import { useAppStore } from '../store/appStore';

const TIER_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  bronze:   { bg: '#FFF3E0', border: '#FF9600', text: '#CC7000' },
  silver:   { bg: '#F5F5F5', border: '#9E9E9E', text: '#616161' },
  gold:     { bg: '#FFF8E1', border: '#FFD900', text: '#CE9700' },
  platinum: { bg: '#E1F5FE', border: '#1CB0F6', text: '#0E8FC5' },
};

export const AchievementsView: React.FC = () => {
  const user = useAppStore((state) => state.user);
  const [earned, setEarned] = useState<Achievement[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadAchievements = async () => {
      if (!user) return;
      setIsLoading(true);
      try {
        const achievements = await getAchievements(user.uid);
        setEarned(achievements);
      } catch (err) {
        console.error('Error loading achievements:', err);
      } finally {
        setIsLoading(false);
      }
    };
    loadAchievements();
  }, [user]);

  const earnedIds = new Set(earned.map(a => a.id));
  const allAchievements = Object.entries(ACHIEVEMENT_DEFINITIONS).map(([id, def]) => {
    const earnedData = earned.find(e => e.id === id);
    return {
      id,
      ...def,
      earnedDate: earnedData?.earnedDate,
      progress: earnedData?.progress,
    };
  });

  const earnedAchievements = allAchievements.filter(a => earnedIds.has(a.id));
  const lockedAchievements = allAchievements.filter(a => !earnedIds.has(a.id));

  if (isLoading) {
    return (
      <div className="min-h-screen bg-duo-gray-light flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <img src="/mascot.png" alt="mascot" className="w-24 h-24 rounded-full object-cover animate-wiggle" />
          <p className="text-duo-green font-extrabold text-xl">読み込み中...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-6">

        {/* Header */}
        <div className="duo-card p-5">
          <div className="flex items-center gap-4">
            <div className="text-5xl">🏆</div>
            <div>
              <h1 className="text-2xl font-black text-duo-dark">アチーブメント</h1>
              <p className="text-duo-gray font-bold text-sm">
                獲得: {earnedAchievements.length} / {allAchievements.length}
              </p>
            </div>
          </div>
          <div className="mt-4">
            <div className="duo-progress-bar" style={{ height: '10px' }}>
              <div
                className="duo-progress-fill"
                style={{ width: `${(earnedAchievements.length / allAchievements.length) * 100}%` }}
              />
            </div>
          </div>
        </div>

        {/* Earned Achievements */}
        {earnedAchievements.length > 0 && (
          <div>
            <h2 className="text-lg font-black text-duo-dark mb-3">✨ 獲得済み</h2>
            <div className="space-y-3">
              {earnedAchievements.map((achievement) => {
                const colors = TIER_COLORS[achievement.tier];
                return (
                  <div
                    key={achievement.id}
                    className="duo-card p-4"
                    style={{ borderColor: colors.border, boxShadow: `0 3px 0 ${colors.border}` }}
                  >
                    <div className="flex items-center gap-4">
                      <div
                        className="w-16 h-16 rounded-2xl flex items-center justify-center text-4xl shrink-0"
                        style={{ background: colors.bg, border: `2px solid ${colors.border}` }}
                      >
                        {achievement.emoji}
                      </div>
                      <div className="flex-1">
                        <h3 className="font-black text-duo-dark text-base leading-tight">
                          {achievement.name}
                        </h3>
                        <p className="text-duo-gray text-sm font-bold mt-0.5">
                          {achievement.description}
                        </p>
                        {achievement.earnedDate && (
                          <p className="text-xs font-bold mt-1" style={{ color: colors.text }}>
                            獲得: {new Date(achievement.earnedDate).toLocaleDateString('ja-JP')}
                          </p>
                        )}
                      </div>
                      <div
                        className="shrink-0 px-3 py-1 rounded-full font-black text-xs uppercase"
                        style={{ background: colors.bg, color: colors.text }}
                      >
                        {achievement.tier}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Locked Achievements */}
        {lockedAchievements.length > 0 && (
          <div>
            <h2 className="text-lg font-black text-duo-dark mb-3">🔒 未獲得</h2>
            <div className="space-y-3">
              {lockedAchievements.map((achievement) => (
                <div
                  key={achievement.id}
                  className="duo-card p-4 opacity-60"
                  style={{ border: '2px solid #e5e5e5' }}
                >
                  <div className="flex items-center gap-4">
                    <div
                      className="w-16 h-16 rounded-2xl flex items-center justify-center text-4xl shrink-0 grayscale"
                      style={{ background: '#f7f7f7', border: '2px solid #e5e5e5' }}
                    >
                      {achievement.emoji}
                    </div>
                    <div className="flex-1">
                      <h3 className="font-black text-duo-gray text-base leading-tight">
                        {achievement.name}
                      </h3>
                      <p className="text-duo-gray text-sm font-bold mt-0.5">
                        {achievement.description}
                      </p>
                      {achievement.progress !== undefined && achievement.target && (
                        <div className="mt-2">
                          <div className="flex items-center justify-between text-xs font-bold text-duo-gray mb-1">
                            <span>進捗: {achievement.progress} / {achievement.target}</span>
                            <span>{Math.round((achievement.progress / achievement.target) * 100)}%</span>
                          </div>
                          <div className="duo-progress-bar" style={{ height: '6px' }}>
                            <div
                              className="h-full rounded-full bg-duo-gray"
                              style={{ width: `${(achievement.progress / achievement.target) * 100}%` }}
                            />
                          </div>
                        </div>
                      )}
                    </div>
                    <div className="shrink-0 text-2xl">🔒</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

      </div>
    </div>
  );
};
