import { useState, type ChangeEvent } from 'react';
import { ArrowLeft, CheckSquare, Square, Loader2, CheckCircle, AlertCircle } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';
import { BUILDER_CHALLENGES, DIFFICULTY_LABELS, DIFFICULTY_COLORS } from '../../data/builderData';
import { evaluateBuilderSession, estimateTokens } from '../../services/claudeService';
import { calcBuilderScore } from '../../types/challenge';
import type { BuilderChallenge as BuilderChallengeType, BuilderChallengeProgress, SessionProgress } from '../../types/challenge';
import type { EvalResult } from '../../services/claudeService';

interface SessionResult {
  session: number;
  evalResult: EvalResult;
  tokensUsed: number;
}

interface InnerProps {
  challenge: BuilderChallengeType;
}

function BuilderChallengeInner({ challenge }: InnerProps) {
  const {
    apiKey,
    builderProgress,
    recordBuilderSession,
    completeBuilderChallenge,
    setView,
  } = useGameStore();

  const [sessionText, setSessionText] = useState('');
  const [evaluating, setEvaluating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionResults, setSessionResults] = useState<SessionResult[]>([]);

  const progress: BuilderChallengeProgress | undefined = builderProgress.find(
    (b: BuilderChallengeProgress) => b.challengeId === challenge.id,
  );
  const currentSession = progress?.currentSession ?? 1;
  const totalTokensUsed = progress?.totalTokensUsed ?? 0;

  const allSessionsCompleted =
    currentSession > challenge.estimatedSessions ||
    (progress?.sessionsData.length ?? 0) >= challenge.estimatedSessions;

  const activeSessionIndex = Math.min(currentSession - 1, challenge.estimatedSessions - 1);
  const activeSessionPlan = challenge.sessionBreakdown[activeSessionIndex];

  const tokenBudget = challenge.baseTokenBudget;
  const tokenBudgetPct = Math.min((totalTokensUsed / tokenBudget) * 100, 100);

  const completedSessionNumbers = new Set<number>([
    ...(progress?.sessionsData.map((s: SessionProgress) => s.session) ?? []),
    ...sessionResults.map((r: SessionResult) => r.session),
  ]);

  async function handleSessionComplete() {
    if (!apiKey || !sessionText.trim() || evaluating) return;
    if (!activeSessionPlan) return;

    setError(null);
    setEvaluating(true);

    let evalResult: EvalResult;
    try {
      evalResult = await evaluateBuilderSession(
        apiKey,
        challenge.title,
        challenge.requirements,
        activeSessionPlan.goal,
        sessionText,
      );
    } catch (e) {
      evalResult = {
        qualityScore: 60,
        feedback: e instanceof Error ? e.message : '評価に失敗しました',
      };
    }

    setEvaluating(false);

    const tokens = estimateTokens(sessionText);
    recordBuilderSession(challenge.id, activeSessionPlan.session, tokens);

    setSessionResults((prev: SessionResult[]) => [
      ...prev,
      { session: activeSessionPlan.session, evalResult, tokensUsed: tokens },
    ]);

    setSessionText('');
  }

  function handleCompleteChallenge() {
    const sessionsUsed = progress?.sessionsData.length ?? challenge.estimatedSessions;
    const avgQuality =
      sessionResults.length > 0
        ? Math.round(
            sessionResults.reduce((s: number, r: SessionResult) => s + r.evalResult.qualityScore, 0) /
              sessionResults.length,
          )
        : 70;

    const score = calcBuilderScore(
      avgQuality,
      totalTokensUsed,
      challenge.baseTokenBudget,
      sessionsUsed,
      challenge.estimatedSessions,
      challenge.difficultyStars,
    );

    completeBuilderChallenge(challenge.id, score);
    setView('map');
  }

  const latestResult: SessionResult | undefined =
    sessionResults.length > 0 ? sessionResults[sessionResults.length - 1] : undefined;

  const showLatestResult =
    latestResult !== undefined &&
    !allSessionsCompleted &&
    latestResult.session === currentSession - 1;

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h1 className="text-xl font-bold text-gray-900">{challenge.title}</h1>
            <span
              className={`px-2.5 py-0.5 rounded-full text-xs font-bold border ${DIFFICULTY_COLORS[challenge.difficulty]}`}
            >
              {DIFFICULTY_LABELS[challenge.difficulty]}
            </span>
          </div>
          <button
            onClick={() => setView('map')}
            className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            マップに戻る
          </button>
        </div>

        {/* Challenge overview card */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-4">
          <p className="text-sm text-gray-700 leading-relaxed">{challenge.description}</p>

          <div className="flex flex-wrap gap-2">
            {challenge.techStack.map((tech) => (
              <span
                key={tech}
                className="px-2.5 py-1 rounded-md bg-indigo-50 text-indigo-700 text-xs font-medium border border-indigo-100"
              >
                {tech}
              </span>
            ))}
          </div>

          <div className="flex gap-6 text-sm text-gray-600">
            <span>
              <span className="font-semibold text-gray-800">{challenge.estimatedSessions}</span>{' '}
              セッション
            </span>
            <span>
              トークン予算:{' '}
              <span className="font-semibold text-gray-800">
                {challenge.baseTokenBudget.toLocaleString()}
              </span>
            </span>
          </div>
        </div>

        {/* Requirements checklist */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-3">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">要件チェックリスト</p>
          <ul className="space-y-2">
            {challenge.requirements.map((req, i) => (
              <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                {allSessionsCompleted ? (
                  <CheckSquare className="w-4 h-4 text-emerald-500 shrink-0 mt-0.5" />
                ) : (
                  <Square className="w-4 h-4 text-gray-300 shrink-0 mt-0.5" />
                )}
                <span>{req}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* Session progress tabs */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-4">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">セッション進捗</p>
          <div className="flex gap-2 flex-wrap">
            {challenge.sessionBreakdown.map((sp) => {
              const isCompleted = completedSessionNumbers.has(sp.session);
              const isCurrent = sp.session === currentSession && !allSessionsCompleted;
              return (
                <div
                  key={sp.session}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors
                    ${isCompleted ? 'bg-emerald-50 border-emerald-200 text-emerald-700' : ''}
                    ${isCurrent && !isCompleted ? 'bg-indigo-50 border-indigo-300 text-indigo-700' : ''}
                    ${!isCurrent && !isCompleted ? 'bg-gray-50 border-gray-200 text-gray-400' : ''}
                  `}
                >
                  {isCompleted && <CheckCircle className="w-3.5 h-3.5" />}
                  Session {sp.session}
                </div>
              );
            })}
          </div>
        </div>

        {/* Current session card */}
        {!allSessionsCompleted && activeSessionPlan && (
          <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-4">
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1">
                Session {activeSessionPlan.session} — ゴール
              </p>
              <p className="text-sm font-medium text-gray-800">{activeSessionPlan.goal}</p>
            </div>

            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">
                成果物
              </p>
              <ul className="space-y-1">
                {activeSessionPlan.deliverables.map((d, i) => (
                  <li key={i} className="flex items-center gap-2 text-sm text-gray-700">
                    <span className="w-1.5 h-1.5 rounded-full bg-indigo-400 shrink-0" />
                    {d}
                  </li>
                ))}
              </ul>
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-medium text-gray-700">
                このセッションで実装したことを説明してください（コードの要点を含めてください）
              </label>
              <textarea
                value={sessionText}
                onChange={(e: ChangeEvent<HTMLTextAreaElement>) => setSessionText(e.target.value)}
                placeholder="実装内容・コードのポイントを記述..."
                className="w-full min-h-36 resize-y rounded-lg border border-gray-300 p-3 text-sm text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-400 focus:border-transparent"
              />
            </div>

            {error && (
              <div className="flex items-start gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
                <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                <span>{error}</span>
              </div>
            )}

            <button
              onClick={handleSessionComplete}
              disabled={evaluating || !sessionText.trim() || !apiKey}
              className="w-full flex items-center justify-center gap-2 py-2.5 rounded-lg bg-indigo-600 text-white text-sm font-semibold disabled:opacity-40 disabled:cursor-not-allowed hover:bg-indigo-700 transition-colors"
            >
              {evaluating ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  評価中...
                </>
              ) : (
                'セッション完了'
              )}
            </button>

            {!apiKey && (
              <p className="text-xs text-amber-600 flex items-center gap-1">
                <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                APIキーが設定されていない場合は設定画面から登録してください
              </p>
            )}
          </div>
        )}

        {/* Latest session result */}
        {showLatestResult && latestResult && (
          <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-4 space-y-2">
            <p className="text-sm font-semibold text-emerald-800">
              Session {latestResult.session} 完了 ✅
            </p>
            <p className="text-sm text-emerald-700">
              スコア: <span className="font-bold">{latestResult.evalResult.qualityScore}/100</span>
            </p>
            <p className="text-xs text-emerald-700">{latestResult.evalResult.feedback}</p>
          </div>
        )}

        {/* Token usage progress bar */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-3">
          <div className="flex items-center justify-between text-sm">
            <p className="font-medium text-gray-700">トークン使用量</p>
            <span className="text-gray-500">
              {totalTokensUsed.toLocaleString()} / {tokenBudget.toLocaleString()}
            </span>
          </div>
          <div className="w-full h-2.5 bg-gray-100 rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${
                tokenBudgetPct >= 90
                  ? 'bg-red-500'
                  : tokenBudgetPct >= 70
                  ? 'bg-amber-500'
                  : 'bg-indigo-500'
              }`}
              style={{ width: `${tokenBudgetPct}%` }}
            />
          </div>
        </div>

        {/* Complete challenge button */}
        {allSessionsCompleted && (
          <div className="bg-white rounded-xl border border-emerald-200 p-5 space-y-3">
            <p className="text-sm font-medium text-emerald-700">
              全セッション完了！チャレンジをクリアしましょう。
            </p>
            <button
              onClick={handleCompleteChallenge}
              className="w-full py-3 rounded-lg bg-emerald-600 text-white font-bold text-sm hover:bg-emerald-700 transition-colors"
            >
              チャレンジ完了！
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

export function BuilderChallenge() {
  const { selectedBuilderId } = useGameStore();
  const challenge = BUILDER_CHALLENGES.find((c) => c.id === selectedBuilderId);
  if (!challenge) return null;
  return <BuilderChallengeInner challenge={challenge} />;
}
