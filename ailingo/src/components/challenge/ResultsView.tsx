import type { ReactNode } from 'react';
import { RotateCcw, ChevronRight, Map, Zap, TrendingUp, Hash } from 'lucide-react';
import type { ChallengeAttempt, Medal } from '../../types/challenge';
import { useGameStore } from '../../store/gameStore';
import { DOJO_CHALLENGES } from '../../data/dojoData';

interface ResultsViewProps {
  attempt: ChallengeAttempt;
  day: number;
  onRetry: () => void;
  onNext: () => void;
  onMap: () => void;
}

function medalEmoji(medal: Medal): string {
  if (medal === 'gold') return '🥇';
  if (medal === 'silver') return '🥈';
  if (medal === 'bronze') return '🥉';
  return '😔';
}

function medalLabel(medal: Medal): string {
  if (medal === 'gold') return 'GOLD';
  if (medal === 'silver') return 'SILVER';
  if (medal === 'bronze') return 'BRONZE';
  return 'NO MEDAL';
}

function medalGlowClass(medal: Medal): string {
  if (medal === 'gold') return 'shadow-yellow-400/50 shadow-2xl';
  if (medal === 'silver') return 'shadow-gray-300/30 shadow-2xl';
  if (medal === 'bronze') return 'shadow-orange-500/40 shadow-2xl';
  return 'shadow-gray-800/20 shadow-lg';
}

function medalRingClass(medal: Medal): string {
  if (medal === 'gold') return 'ring-4 ring-yellow-400/70 bg-yellow-950/50';
  if (medal === 'silver') return 'ring-4 ring-gray-400/50 bg-gray-800/70';
  if (medal === 'bronze') return 'ring-4 ring-orange-400/50 bg-orange-950/50';
  return 'ring-2 ring-gray-700/40 bg-gray-900/60';
}

function medalScoreColor(medal: Medal): string {
  if (medal === 'gold') return 'text-yellow-400';
  if (medal === 'silver') return 'text-gray-300';
  if (medal === 'bronze') return 'text-orange-400';
  return 'text-gray-500';
}

function medalLabelColor(medal: Medal): string {
  if (medal === 'gold') return 'text-yellow-500 bg-yellow-950/60 border-yellow-600/50';
  if (medal === 'silver') return 'text-gray-300 bg-gray-800/60 border-gray-600/50';
  if (medal === 'bronze') return 'text-orange-400 bg-orange-950/60 border-orange-600/50';
  return 'text-gray-500 bg-gray-900/60 border-gray-700/50';
}

function medalBgGradient(medal: Medal): string {
  if (medal === 'gold') return 'from-yellow-950/30 via-gray-950 to-gray-950';
  if (medal === 'silver') return 'from-gray-800/30 via-gray-950 to-gray-950';
  if (medal === 'bronze') return 'from-orange-950/30 via-gray-950 to-gray-950';
  return 'from-gray-900/30 via-gray-950 to-gray-950';
}

function ScoreStat({
  label,
  value,
  sub,
  icon,
}: {
  label: string;
  value: string | number;
  sub?: string;
  icon?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-1.5 p-3 rounded-xl bg-gray-800/60 border border-gray-700/60">
      <div className="flex items-center gap-1 text-[10px] font-semibold text-gray-500 uppercase tracking-wider">
        {icon}
        {label}
      </div>
      <div className="text-lg font-black text-white tabular-nums">{value}</div>
      {sub && <div className="text-[10px] text-gray-600">{sub}</div>}
    </div>
  );
}

export function ResultsView({ attempt, day, onRetry, onNext, onMap }: ResultsViewProps) {
  const { medal, score, qualityScore, inputTokens, outputTokens, totalTokens, response } = attempt;
  const dojoProgress = useGameStore((s) => s.dojoProgress);
  const dayProgress = dojoProgress.find((d) => d.day === day);
  const attemptCount = dayProgress?.attempts ?? 1;

  const preview = response.length > 200 ? response.slice(0, 200) + '…' : response;

  const dojoChallenge = DOJO_CHALLENGES.find((c) => c.day === day);
  const goldTokenLimit = dojoChallenge?.tokenLimits.gold ?? totalTokens;
  const tokenEffPct = Math.min(100, Math.max(5, (goldTokenLimit / Math.max(totalTokens, 1)) * 100));
  const qualityPct = qualityScore;

  return (
    <div className={`min-h-screen bg-gradient-to-b ${medalBgGradient(medal)} text-white flex flex-col`}>
      <div className="max-w-lg mx-auto w-full px-4 py-8 flex flex-col gap-6">

        <div className="text-center">
          <div className="text-[10px] text-gray-600 font-mono uppercase tracking-[0.2em] mb-1">
            Day {day} · Results
          </div>
        </div>

        <div className="flex flex-col items-center gap-3">
          <div
            className={`
              w-32 h-32 rounded-full flex items-center justify-center text-7xl
              ${medalRingClass(medal)} ${medalGlowClass(medal)}
              animate-[bounce_0.6s_ease-out_1]
            `}
          >
            {medalEmoji(medal)}
          </div>

          <div className={`text-xs font-black tracking-[0.25em] px-3 py-1 rounded-full border ${medalLabelColor(medal)}`}>
            {medalLabel(medal)}
          </div>

          <div
            className={`
              text-6xl font-black tabular-nums leading-none
              ${medalScoreColor(medal)}
              [filter:drop-shadow(0_0_20px_currentColor)]
            `}
          >
            {score.toLocaleString()}
          </div>
          <div className="text-xs text-gray-500 font-semibold tracking-widest uppercase">points</div>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <ScoreStat
            label="Quality Score"
            value={qualityScore}
            sub="/ 100"
            icon={<TrendingUp size={10} />}
          />
          <ScoreStat
            label="Attempts"
            value={attemptCount}
            sub={attemptCount === 1 ? 'one-shot!' : undefined}
            icon={<Hash size={10} />}
          />
          <ScoreStat
            label="Input Tokens"
            value={inputTokens.toLocaleString()}
            icon={<Zap size={10} />}
          />
          <ScoreStat
            label="Output Tokens"
            value={outputTokens.toLocaleString()}
            icon={<Zap size={10} />}
          />
        </div>

        <div className="space-y-3 p-4 rounded-xl bg-gray-900/70 border border-gray-800">
          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-xs">
              <div className="flex items-center gap-1.5 text-gray-400">
                <TrendingUp size={12} />
                <span>Quality</span>
              </div>
              <span className="font-mono text-gray-300 font-semibold">{qualityPct}/100</span>
            </div>
            <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-1000 delay-300 ${
                  qualityPct >= 80 ? 'bg-emerald-500' : qualityPct >= 50 ? 'bg-yellow-500' : 'bg-red-500'
                }`}
                style={{ width: `${qualityPct}%` }}
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-xs">
              <div className="flex items-center gap-1.5 text-gray-400">
                <Zap size={12} />
                <span>Token Efficiency</span>
              </div>
              <span className="font-mono text-gray-300 font-semibold">{totalTokens.toLocaleString()} used</span>
            </div>
            <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-1000 delay-500 ${
                  medal === 'gold' ? 'bg-yellow-400' : medal === 'silver' ? 'bg-gray-400' : medal === 'bronze' ? 'bg-orange-500' : 'bg-gray-600'
                }`}
                style={{ width: `${Math.max(5, Math.min(100, tokenEffPct))}%` }}
              />
            </div>
            <div className="flex justify-between text-[10px] text-gray-600">
              <span>gold limit: {goldTokenLimit.toLocaleString()} tokens</span>
              <span className={totalTokens <= goldTokenLimit ? 'text-yellow-600' : 'text-red-700'}>
                {totalTokens <= goldTokenLimit ? 'within limit' : 'over limit'}
              </span>
            </div>
          </div>
        </div>

        {response && (
          <div className="space-y-2">
            <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Response Preview</div>
            <div className="p-3 rounded-xl bg-gray-900/80 border border-gray-800 text-xs text-gray-400 leading-relaxed font-mono whitespace-pre-wrap break-words">
              {preview}
            </div>
          </div>
        )}

        <div className="grid grid-cols-3 gap-2 pt-1">
          <button
            onClick={onRetry}
            className="flex flex-col items-center gap-1.5 py-3.5 rounded-xl border border-gray-700 bg-gray-800/60 hover:bg-gray-800 hover:border-gray-600 active:scale-95 transition-all duration-200 text-xs font-semibold text-gray-300 group"
          >
            <RotateCcw size={16} className="group-hover:rotate-[-45deg] transition-transform duration-300" />
            再挑戦
          </button>
          <button
            onClick={onNext}
            className={`
              flex flex-col items-center gap-1.5 py-3.5 rounded-xl border active:scale-95 transition-all duration-200 text-xs font-semibold group
              ${medal === 'gold'
                ? 'border-yellow-600/60 bg-yellow-950/50 hover:bg-yellow-950/80 hover:border-yellow-500 text-yellow-300'
                : 'border-emerald-700/60 bg-emerald-950/50 hover:bg-emerald-950/80 hover:border-emerald-500 text-emerald-300'
              }
            `}
          >
            <ChevronRight size={16} className="group-hover:translate-x-0.5 transition-transform" />
            次のDOJOへ
          </button>
          <button
            onClick={onMap}
            className="flex flex-col items-center gap-1.5 py-3.5 rounded-xl border border-gray-700 bg-gray-800/60 hover:bg-gray-800 hover:border-gray-600 active:scale-95 transition-all duration-200 text-xs font-semibold text-gray-300 group"
          >
            <Map size={16} />
            マップに戻る
          </button>
        </div>

      </div>
    </div>
  );
}
