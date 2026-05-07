import { useState, type ChangeEvent } from 'react';
import { ArrowLeft, Trophy, ChevronDown, ChevronUp, Loader2, Send, AlertCircle } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';
import { DOJO_CHALLENGES } from '../../data/dojoData';
import { runDojoChallenge, evaluateResponse, estimateTokens } from '../../services/claudeService';
import { calcDojoScore } from '../../types/challenge';
import type { ChallengeAttempt, Medal, DojoDayProgress } from '../../types/challenge';

const MEDAL_LABELS: Record<Medal, string> = {
  gold: '🥇 ゴールド',
  silver: '🥈 シルバー',
  bronze: '🥉 ブロンズ',
  none: '未達成',
};

const MEDAL_COLORS: Record<Medal, string> = {
  gold: 'text-yellow-600 bg-yellow-50 border-yellow-300',
  silver: 'text-slate-600 bg-slate-50 border-slate-300',
  bronze: 'text-orange-700 bg-orange-50 border-orange-300',
  none: 'text-gray-600 bg-gray-50 border-gray-300',
};

export function DojoChallenge() {
  const { selectedDojoDay, apiKey, dojoProgress, recordDojoAttempt, setLastAttempt, setView } =
    useGameStore();

  const [prompt, setPrompt] = useState('');
  const [hintsOpen, setHintsOpen] = useState(false);
  const [revealedHints, setRevealedHints] = useState(0);
  const [loading, setLoading] = useState(false);
  const [evaluating, setEvaluating] = useState(false);
  const [response, setResponse] = useState<string | null>(null);
  const [attempt, setAttempt] = useState<ChallengeAttempt | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (selectedDojoDay === null) return null;

  const challenge = DOJO_CHALLENGES[selectedDojoDay - 1];
  if (!challenge) return null;

  const dayProgress: DojoDayProgress | undefined = dojoProgress.find((d: DojoDayProgress) => d.day === selectedDojoDay);
  const previouslyCompleted = dayProgress?.completed ?? false;
  const attempts = dayProgress?.attempts ?? 0;

  const estimatedTokens = estimateTokens(prompt);

  async function handleSubmit() {
    if (selectedDojoDay === null || !apiKey || !prompt.trim()) return;
    setError(null);
    setResponse(null);
    setAttempt(null);
    setLoading(true);

    let claudeResponse;
    try {
      claudeResponse = await runDojoChallenge(apiKey, prompt, challenge.task);
    } catch (e) {
      setError(e instanceof Error ? e.message : '送信に失敗しました');
      setLoading(false);
      return;
    }

    setResponse(claudeResponse.content);
    setLoading(false);
    setEvaluating(true);

    let evalResult;
    try {
      evalResult = await evaluateResponse(
        apiKey,
        challenge.task,
        claudeResponse.content,
        challenge.evaluationCriteria,
      );
    } catch {
      evalResult = { qualityScore: 50, feedback: '評価に失敗しました' };
    }

    setEvaluating(false);

    const { score, medal } = calcDojoScore(
      evalResult.qualityScore,
      claudeResponse.totalTokens,
      challenge.tokenLimits.gold,
      attempts + 1,
    );

    const newAttempt: ChallengeAttempt = {
      prompt,
      response: claudeResponse.content,
      inputTokens: claudeResponse.inputTokens,
      outputTokens: claudeResponse.outputTokens,
      totalTokens: claudeResponse.totalTokens,
      qualityScore: evalResult.qualityScore,
      score,
      medal,
      timestamp: new Date().toISOString(),
    };

    setAttempt(newAttempt);
    recordDojoAttempt(selectedDojoDay, newAttempt);
    setLastAttempt(newAttempt);
  }

  function handleRevealHint() {
    if (revealedHints < challenge.hints.length) {
      setRevealedHints((n: number) => n + 1);
    }
  }

  const canSubmit = !!apiKey && prompt.trim().length > 0 && !loading && !evaluating;

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header */}
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-gray-900">
            Day {challenge.day} — {challenge.skill}
          </h1>
          <button
            onClick={() => setView('map')}
            className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            マップに戻る
          </button>
        </div>

        {/* Challenge description card */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-4">
          <div>
            <p className="text-sm font-semibold text-indigo-600 mb-1">{challenge.theme}</p>
            <p className="text-sm text-gray-700 leading-relaxed">{challenge.description}</p>
          </div>

          <div className="bg-gray-50 rounded-lg p-4 border border-gray-100">
            <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">課題</p>
            <pre className="text-sm text-gray-800 font-mono whitespace-pre-wrap leading-relaxed">
              {challenge.task}
            </pre>
          </div>

          <div>
            <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1">
              理想の出力
            </p>
            <p className="text-sm text-gray-700">{challenge.targetOutput}</p>
          </div>
        </div>

        {/* Token limits card */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3">
            トークン制限
          </p>
          <div className="flex gap-4">
            <div className="flex items-center gap-1.5 text-sm text-yellow-700">
              <span>🥇</span>
              <span>≤ {challenge.tokenLimits.gold} トークン</span>
            </div>
            <div className="flex items-center gap-1.5 text-sm text-slate-600">
              <span>🥈</span>
              <span>≤ {challenge.tokenLimits.silver} トークン</span>
            </div>
            <div className="flex items-center gap-1.5 text-sm text-orange-700">
              <span>🥉</span>
              <span>≤ {challenge.tokenLimits.bronze} トークン</span>
            </div>
          </div>
        </div>

        {/* Hints accordion */}
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <button
            className="w-full flex items-center justify-between px-5 py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
            onClick={() => setHintsOpen((o: boolean) => !o)}
          >
            <span>ヒント ({challenge.hints.length}件)</span>
            {hintsOpen ? (
              <ChevronUp className="w-4 h-4 text-gray-400" />
            ) : (
              <ChevronDown className="w-4 h-4 text-gray-400" />
            )}
          </button>
          {hintsOpen && (
            <div className="px-5 pb-4 space-y-2 border-t border-gray-100">
              {challenge.hints.slice(0, revealedHints).map((hint, i) => (
                <div key={i} className="flex gap-2 text-sm text-gray-700">
                  <span className="text-indigo-400 font-bold shrink-0">{i + 1}.</span>
                  <span>{hint}</span>
                </div>
              ))}
              {revealedHints < challenge.hints.length && (
                <button
                  onClick={handleRevealHint}
                  className="mt-2 text-xs text-indigo-600 hover:text-indigo-800 font-medium underline"
                >
                  {revealedHints === 0 ? '最初のヒントを見る' : '次のヒントを見る'}
                </button>
              )}
              {revealedHints === challenge.hints.length && revealedHints > 0 && (
                <p className="mt-1 text-xs text-gray-400">ヒントをすべて表示しました</p>
              )}
            </div>
          )}
        </div>

        {/* Prompt editor */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-3">
          <label className="block text-sm font-medium text-gray-700">
            あなたのプロンプトを書いてください
          </label>
          <textarea
            value={prompt}
            onChange={(e: ChangeEvent<HTMLTextAreaElement>) => setPrompt(e.target.value)}
            placeholder="ここにプロンプトを入力..."
            className="w-full min-h-48 resize-y rounded-lg border border-gray-300 p-3 font-mono text-sm text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-400 focus:border-transparent"
          />
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400">
              推定トークン数: <span className="font-semibold text-gray-600">{estimatedTokens}</span>
            </span>
            <button
              onClick={handleSubmit}
              disabled={!canSubmit}
              className="flex items-center gap-2 px-5 py-2 rounded-lg bg-indigo-600 text-white text-sm font-semibold disabled:opacity-40 disabled:cursor-not-allowed hover:bg-indigo-700 transition-colors"
            >
              <Send className="w-4 h-4" />
              送信
            </button>
          </div>
          {!apiKey && (
            <p className="text-xs text-amber-600 flex items-center gap-1">
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              APIキーが設定されていない場合は設定画面から登録してください
            </p>
          )}
        </div>

        {/* Loading state */}
        {loading && (
          <div className="bg-white rounded-xl border border-gray-200 p-6 flex flex-col items-center gap-3">
            <Loader2 className="w-7 h-7 animate-spin text-indigo-500" />
            <p className="text-sm text-gray-600">Claudeに送信中...</p>
          </div>
        )}

        {/* Response + evaluation */}
        {response !== null && !loading && (
          <div className="bg-white rounded-xl border border-gray-200 p-5 space-y-4">
            <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Claudeの回答
            </p>
            <div className="rounded-lg border border-gray-200 bg-gray-50 p-4 text-sm text-gray-800 leading-relaxed whitespace-pre-wrap">
              {response}
            </div>

            {evaluating && (
              <div className="flex items-center gap-2 text-sm text-gray-500">
                <Loader2 className="w-4 h-4 animate-spin text-indigo-400" />
                採点中...
              </div>
            )}

            {attempt && !evaluating && (
              <div className={`rounded-lg border p-4 space-y-2 ${MEDAL_COLORS[attempt.medal as Medal]}`}>
                <div className="flex items-center gap-2">
                  <Trophy className="w-5 h-5" />
                  <span className="font-bold text-sm">{MEDAL_LABELS[attempt.medal as Medal]}</span>
                  <span className="ml-auto text-sm font-semibold">{attempt.score} pts</span>
                </div>
                <p className="text-xs">
                  品質スコア: {attempt.qualityScore}/100 ・ トークン使用: {attempt.totalTokens}
                </p>
                <div className="pt-1">
                  <button
                    onClick={() => setView('results')}
                    className="w-full py-2 rounded-lg bg-indigo-600 text-white text-sm font-semibold hover:bg-indigo-700 transition-colors"
                  >
                    結果画面へ
                  </button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Error state */}
        {error && (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex gap-2 text-sm text-red-700">
            <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}

        {/* Previous attempt info */}
        {previouslyCompleted && !attempt && dayProgress && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-1">
            <div className="flex items-center gap-2 text-sm font-medium text-gray-700">
              <Trophy className="w-4 h-4 text-yellow-500" />
              <span>前回の記録</span>
              <span className={`ml-auto px-2 py-0.5 rounded-full text-xs font-semibold border ${MEDAL_COLORS[dayProgress.medal]}`}>
                {MEDAL_LABELS[dayProgress.medal]}
              </span>
            </div>
            <p className="text-xs text-gray-500">
              スコア: {dayProgress.score} ・ 挑戦回数: {dayProgress.attempts}回
            </p>
            <p className="text-xs text-indigo-600">再挑戦して記録を更新できます</p>
          </div>
        )}
      </div>
    </div>
  );
}
