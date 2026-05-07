import { Lock, Trophy, Star, ChevronRight, CheckCircle2, Sword, Hammer, Sparkles } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';
import { DOJO_CHALLENGES } from '../../data/dojoData';
import { BUILDER_CHALLENGES, DIFFICULTY_LABELS, DIFFICULTY_COLORS } from '../../data/builderData';
import { UsageMeter } from './UsageMeter';
import type { Medal, DojoDayProgress, BuilderChallengeProgress } from '../../types/challenge';

function MedalIcon({ medal }: { medal: Medal }) {
  if (medal === 'gold') return <span className="text-lg leading-none">🥇</span>;
  if (medal === 'silver') return <span className="text-lg leading-none">🥈</span>;
  if (medal === 'bronze') return <span className="text-lg leading-none">🥉</span>;
  return <span className="text-lg leading-none opacity-20">⬜</span>;
}

function DojoNode({
  day,
  skill,
  progress,
  onClick,
}: {
  day: number;
  skill: string;
  progress: DojoDayProgress | undefined;
  onClick: () => void;
}) {
  const completed = progress?.completed ?? false;
  const medal = progress?.medal ?? 'none';

  return (
    <button
      onClick={onClick}
      className={`
        flex flex-col items-center gap-1.5 p-2.5 rounded-xl border-2 transition-all duration-200
        hover:scale-105 active:scale-95 min-w-[68px] flex-1
        ${completed
          ? 'border-emerald-500 bg-emerald-950/70 shadow-lg shadow-emerald-500/20'
          : 'border-gray-700 bg-gray-800/50 hover:border-emerald-600 hover:bg-emerald-950/30'
        }
      `}
    >
      <div className="text-[10px] font-bold text-gray-500 uppercase tracking-wide">Day {day}</div>
      <MedalIcon medal={medal} />
      <div className="text-[10px] text-gray-400 text-center leading-tight max-w-[64px] truncate" title={skill}>
        {skill}
      </div>
    </button>
  );
}

function StarsDisplay({ count, max = 5 }: { count: number; max?: number }) {
  return (
    <div className="flex gap-0.5">
      {Array.from({ length: max }, (_, i) => (
        <Star
          key={i}
          size={11}
          className={i < count ? 'text-yellow-400 fill-yellow-400' : 'text-gray-700 fill-gray-700'}
        />
      ))}
    </div>
  );
}

function BuilderCard({
  challenge,
  progress,
  locked,
  onClick,
}: {
  challenge: (typeof BUILDER_CHALLENGES)[number];
  progress: BuilderChallengeProgress | undefined;
  locked: boolean;
  onClick: () => void;
}) {
  const sessionPct = progress
    ? Math.min(100, (progress.currentSession / challenge.estimatedSessions) * 100)
    : 0;
  const colorClass = DIFFICULTY_COLORS[challenge.difficulty] ?? 'text-gray-400 bg-gray-800 border-gray-600';

  return (
    <button
      onClick={locked ? undefined : onClick}
      disabled={locked}
      className={`
        relative text-left p-3 rounded-xl border-2 transition-all duration-200 w-full
        ${locked
          ? 'border-gray-800 bg-gray-900/40 cursor-not-allowed opacity-50'
          : progress?.completed
          ? 'border-blue-500/70 bg-blue-950/50 hover:border-blue-400 hover:scale-[1.02] active:scale-[0.99]'
          : 'border-blue-800/50 bg-blue-950/20 hover:border-blue-600 hover:bg-blue-950/50 hover:scale-[1.02] active:scale-[0.99]'
        }
      `}
    >
      {locked && (
        <div className="absolute inset-0 flex items-center justify-center rounded-xl bg-gray-900/50 backdrop-blur-[1px] z-10">
          <Lock size={16} className="text-gray-600" />
        </div>
      )}
      <div className="flex items-start justify-between gap-1.5 mb-1.5">
        <span className="text-sm font-semibold text-white leading-tight">{challenge.title}</span>
        {progress?.completed && <CheckCircle2 size={14} className="text-blue-400 shrink-0 mt-0.5" />}
      </div>
      <div className="flex items-center justify-between mb-2">
        <StarsDisplay count={challenge.difficultyStars} />
        <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded border ${colorClass}`}>
          {DIFFICULTY_LABELS[challenge.difficulty]}
        </span>
      </div>
      {progress?.started && !progress.completed && (
        <div className="space-y-1">
          <div className="flex justify-between text-[10px] text-gray-400">
            <span>Session {progress.currentSession}/{challenge.estimatedSessions}</span>
            <span>{Math.round(sessionPct)}%</span>
          </div>
          <div className="h-1.5 bg-gray-800 rounded-full overflow-hidden">
            <div
              className="h-full bg-blue-500 rounded-full transition-all duration-500"
              style={{ width: `${sessionPct}%` }}
            />
          </div>
        </div>
      )}
      {!progress?.started && (
        <div className="text-[10px] text-gray-500">
          ~{challenge.estimatedSessions} session{challenge.estimatedSessions !== 1 ? 's' : ''}
        </div>
      )}
    </button>
  );
}

function StageDot({ active, color }: { active: boolean; color: string }) {
  return (
    <div
      className={`
        absolute left-6 top-7 w-4 h-4 rounded-full border-2 -translate-x-1/2 z-10
        ${active
          ? `${color} shadow-lg`
          : 'bg-gray-700 border-gray-600 shadow-none'
        }
      `}
    />
  );
}

export function WorldMap() {
  const {
    stage,
    dojoProgress,
    builderProgress,
    totalScore,
    streak,
    sprint,
    weekly,
    goToDojo,
    goToBuilder,
    setView,
  } = useGameStore();

  const dojoComplete = dojoProgress.every((d) => d.completed);
  const dojoCompletionPct = Math.round((dojoProgress.filter((d) => d.completed).length / 7) * 100);

  const hardChallenges = BUILDER_CHALLENGES.filter((c) => c.difficulty === 'hard');
  const hardAllDone = hardChallenges.length > 0 && hardChallenges.every((c) =>
    builderProgress.find((p) => p.challengeId === c.id)?.completed
  );

  const builderLocked = stage === 'dojo';
  const creatorLocked = !hardAllDone;

  const groupedBuilder: Record<string, typeof BUILDER_CHALLENGES> = {};
  for (const ch of BUILDER_CHALLENGES) {
    if (!groupedBuilder[ch.difficulty]) groupedBuilder[ch.difficulty] = [];
    groupedBuilder[ch.difficulty].push(ch);
  }
  const difficultyOrder = ['easy', 'normal', 'hard', 'expert', 'master'] as const;

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <div className="max-w-3xl mx-auto px-4 py-6 space-y-5">

        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-black tracking-tight bg-gradient-to-r from-emerald-400 via-blue-400 to-purple-400 bg-clip-text text-transparent">
              AI CHALLENGE
            </h1>
            <p className="text-xs text-gray-500 mt-0.5">プロンプトエンジニアリング道場</p>
          </div>
          <div className="flex items-center gap-5">
            <div className="text-center">
              <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-0.5">連続</div>
              <div className="text-xl font-black text-orange-400 leading-none">{streak}<span className="text-base">🔥</span></div>
            </div>
            <div className="text-center">
              <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-0.5">総得点</div>
              <div className="text-xl font-black text-yellow-400 leading-none">{totalScore.toLocaleString()}</div>
            </div>
          </div>
        </div>

        <UsageMeter sprint={sprint} weekly={weekly} />

        <div className="relative">
          <div className="absolute left-6 top-0 bottom-0 w-0.5 bg-gradient-to-b from-emerald-500/40 via-blue-500/40 to-purple-500/40" />

          <div className="space-y-4">

            <div className="relative">
              <StageDot active color="bg-emerald-500 border-emerald-300 shadow-emerald-500/60" />
              <div className="ml-14 border-2 border-emerald-700/70 bg-gradient-to-br from-emerald-950/90 to-gray-900/90 rounded-2xl p-4 shadow-xl shadow-emerald-950/40">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div className="w-8 h-8 rounded-lg bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center">
                      <Sword size={16} className="text-emerald-400" />
                    </div>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-[10px] font-black text-emerald-500 tracking-widest uppercase">Stage 1</span>
                        {dojoComplete && (
                          <span className="text-[10px] bg-emerald-500 text-black font-black px-1.5 py-0.5 rounded-full">
                            DOJO完了
                          </span>
                        )}
                      </div>
                      <h2 className="text-lg font-black text-white leading-tight">DOJO</h2>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-2xl font-black text-emerald-400 leading-none">{dojoCompletionPct}%</div>
                    <div className="text-[10px] text-gray-500 mt-0.5">完了</div>
                  </div>
                </div>

                <div className="w-full h-1.5 bg-gray-800/80 rounded-full mb-4 overflow-hidden">
                  <div
                    className="h-full bg-gradient-to-r from-emerald-600 to-emerald-400 rounded-full transition-all duration-700"
                    style={{ width: `${dojoCompletionPct}%` }}
                  />
                </div>

                <div className="flex flex-wrap gap-1.5">
                  {DOJO_CHALLENGES.map((ch) => {
                    const prog = dojoProgress.find((d) => d.day === ch.day);
                    return (
                      <DojoNode
                        key={ch.day}
                        day={ch.day}
                        skill={ch.skill}
                        progress={prog}
                        onClick={() => goToDojo(ch.day)}
                      />
                    );
                  })}
                </div>
              </div>
            </div>

            <div className="relative">
              <StageDot
                active={!builderLocked}
                color="bg-blue-500 border-blue-300 shadow-blue-500/60"
              />
              <div
                className={`ml-14 border-2 rounded-2xl p-4 shadow-xl transition-all duration-500 ${
                  builderLocked
                    ? 'border-gray-800 bg-gray-900/60 opacity-60'
                    : 'border-blue-700/70 bg-gradient-to-br from-blue-950/90 to-gray-900/90 shadow-blue-950/40'
                }`}
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center border ${
                      builderLocked
                        ? 'bg-gray-800/50 border-gray-700'
                        : 'bg-blue-500/20 border-blue-500/40'
                    }`}>
                      {builderLocked
                        ? <Lock size={15} className="text-gray-600" />
                        : <Hammer size={16} className="text-blue-400" />
                      }
                    </div>
                    <div>
                      <span className={`text-[10px] font-black tracking-widest uppercase ${builderLocked ? 'text-gray-600' : 'text-blue-500'}`}>
                        Stage 2
                      </span>
                      <h2 className={`text-lg font-black leading-tight ${builderLocked ? 'text-gray-600' : 'text-white'}`}>
                        BUILDER
                      </h2>
                    </div>
                  </div>
                  {builderLocked && (
                    <div className="text-xs text-gray-600 text-right leading-snug">
                      <div>DOJOを完了</div>
                      <div>すると解放</div>
                    </div>
                  )}
                </div>

                {!builderLocked && (
                  <div className="space-y-4">
                    {difficultyOrder.map((diff) => {
                      const challenges = groupedBuilder[diff];
                      if (!challenges?.length) return null;
                      return (
                        <div key={diff}>
                          <div className="flex items-center gap-2 mb-2">
                            <span className={`text-[10px] font-black px-2 py-0.5 rounded border ${DIFFICULTY_COLORS[diff]}`}>
                              {DIFFICULTY_LABELS[diff]}
                            </span>
                            <div className="h-px flex-1 bg-gray-800" />
                          </div>
                          <div className="grid grid-cols-2 gap-2">
                            {challenges.map((ch) => {
                              const prog = builderProgress.find((p) => p.challengeId === ch.id);
                              const cardLocked = ch.difficulty === 'master' && !hardAllDone;
                              return (
                                <BuilderCard
                                  key={ch.id}
                                  challenge={ch}
                                  progress={prog}
                                  locked={cardLocked}
                                  onClick={() => goToBuilder(ch.id)}
                                />
                              );
                            })}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>

            <div className="relative">
              <StageDot
                active={!creatorLocked}
                color="bg-purple-500 border-purple-300 shadow-purple-500/60"
              />
              <div
                className={`ml-14 border-2 rounded-2xl p-4 shadow-xl transition-all duration-500 ${
                  creatorLocked
                    ? 'border-gray-800 bg-gray-900/60 opacity-50'
                    : 'border-purple-700/70 bg-gradient-to-br from-purple-950/90 to-gray-900/90 shadow-purple-950/40'
                }`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center border ${
                      creatorLocked
                        ? 'bg-gray-800/50 border-gray-700'
                        : 'bg-purple-500/20 border-purple-500/40'
                    }`}>
                      {creatorLocked
                        ? <Lock size={15} className="text-gray-600" />
                        : <Sparkles size={16} className="text-purple-400" />
                      }
                    </div>
                    <div>
                      <span className={`text-[10px] font-black tracking-widest uppercase ${creatorLocked ? 'text-gray-600' : 'text-purple-400'}`}>
                        Stage 3
                      </span>
                      <h2 className={`text-lg font-black leading-tight ${creatorLocked ? 'text-gray-600' : 'text-white'}`}>
                        CREATOR
                      </h2>
                    </div>
                  </div>
                  <div className={`text-right text-xs ${creatorLocked ? 'text-gray-600' : 'text-purple-400'}`}>
                    {creatorLocked ? (
                      <>
                        <div>HARDを全て</div>
                        <div>クリアで解放</div>
                      </>
                    ) : (
                      <span className="text-sm font-black text-purple-300">COMING SOON</span>
                    )}
                  </div>
                </div>
                {!creatorLocked && (
                  <div className="mt-4 text-center py-6 border border-dashed border-purple-700/40 rounded-xl">
                    <Trophy size={32} className="text-purple-400/50 mx-auto mb-2" />
                    <p className="text-xs text-gray-500">クリエイターステージは近日公開予定です</p>
                    <p className="text-[10px] text-gray-600 mt-1">オリジナルAIプロダクトを世界へ</p>
                  </div>
                )}
              </div>
            </div>

          </div>
        </div>

        <button
          onClick={() => setView('leaderboard')}
          className="w-full flex items-center justify-center gap-2 py-3.5 rounded-xl border border-gray-700 bg-gray-800/50 hover:bg-gray-800 hover:border-yellow-600/50 transition-all duration-200 text-sm font-semibold text-gray-300 hover:text-yellow-300 group"
        >
          <Trophy size={16} className="text-yellow-400" />
          週間ランキングを見る
          <ChevronRight size={16} className="group-hover:translate-x-1 transition-transform duration-200" />
        </button>

      </div>
    </div>
  );
}
