import { useEffect, useState } from 'react';
import { Zap, Calendar } from 'lucide-react';
import type { SprintUsage, WeeklyUsage } from '../../types/challenge';

interface UsageMeterProps {
  sprint: SprintUsage;
  weekly: WeeklyUsage;
}

function formatCountdown(endIso: string): string {
  const diff = Math.max(0, new Date(endIso).getTime() - Date.now());
  const totalSecs = Math.floor(diff / 1000);
  const hours = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;
  if (hours > 0) {
    return `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}`;
  }
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

function formatTokens(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
}

function sprintBarColor(pct: number): string {
  if (pct > 85) return 'bg-red-500';
  if (pct > 60) return 'bg-yellow-400';
  return 'bg-emerald-500';
}

function sprintTextColor(pct: number): string {
  if (pct > 85) return 'text-red-400';
  if (pct > 60) return 'text-yellow-400';
  return 'text-emerald-400';
}

export function UsageMeter({ sprint, weekly }: UsageMeterProps) {
  const [, tick] = useState(0);

  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, []);

  const sprintPct = Math.min(100, (sprint.tokensUsed / sprint.tokensLimit) * 100);
  const weeklyPct = Math.min(100, (weekly.tokensUsed / weekly.tokensLimit) * 100);
  const sprintExpired = Date.now() >= new Date(sprint.windowEnd).getTime();

  return (
    <div className="bg-gray-900 border border-gray-700/80 rounded-xl p-3 space-y-3">
      <div className="space-y-1.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <Zap size={13} className="text-yellow-400" />
            <span className="text-xs font-semibold text-gray-300 uppercase tracking-wide">Sprint</span>
            {sprintExpired ? (
              <span className="text-xs text-red-400 font-mono font-bold">ENDED</span>
            ) : (
              <span className={`text-xs font-mono font-semibold ${sprintTextColor(sprintPct)}`}>
                {formatCountdown(sprint.windowEnd)}
              </span>
            )}
          </div>
          <span className="text-xs font-mono text-gray-400">
            <span className={sprintTextColor(sprintPct)}>{formatTokens(sprint.tokensUsed)}</span>
            <span className="text-gray-600"> / </span>
            {formatTokens(sprint.tokensLimit)}
          </span>
        </div>
        <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-500 ${sprintBarColor(sprintPct)}`}
            style={{ width: `${sprintPct}%` }}
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <Calendar size={13} className="text-blue-400" />
            <span className="text-xs font-semibold text-gray-300 uppercase tracking-wide">Weekly</span>
          </div>
          <span className="text-xs font-mono text-gray-400">
            <span className="text-blue-400">{formatTokens(weekly.tokensUsed)}</span>
            <span className="text-gray-600"> / </span>
            {formatTokens(weekly.tokensLimit)}
          </span>
        </div>
        <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
          <div
            className="h-full rounded-full bg-blue-500 transition-all duration-500"
            style={{ width: `${weeklyPct}%` }}
          />
        </div>
      </div>
    </div>
  );
}
