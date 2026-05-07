// Claude API service (browser-direct via user's API key)
// Mirrors the existing kfit aiService.ts pattern for Anthropic calls.

export interface ClaudeResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export interface EvalResult {
  qualityScore: number;   // 0-100
  feedback: string;
}

const ANTHROPIC_API = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5-20251001';

async function callClaude(
  apiKey: string,
  messages: { role: 'user' | 'assistant'; content: string }[],
  system?: string,
  maxTokens = 1024,
): Promise<ClaudeResponse> {
  const body: Record<string, unknown> = {
    model: MODEL,
    max_tokens: maxTokens,
    messages,
  };
  if (system) body.system = system;

  const res = await fetch(ANTHROPIC_API, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    const msg = (err as { error?: { message?: string } })?.error?.message ?? `API error ${res.status}`;
    throw new Error(msg);
  }

  const data = await res.json() as {
    content: Array<{ text: string }>;
    usage: { input_tokens: number; output_tokens: number };
  };

  return {
    content: data.content[0].text,
    inputTokens: data.usage.input_tokens,
    outputTokens: data.usage.output_tokens,
    totalTokens: data.usage.input_tokens + data.usage.output_tokens,
  };
}

// ── DOJO: run a challenge ─────────────────────────────────────────────────────

export async function runDojoChallenge(
  apiKey: string,
  userPrompt: string,
  task: string,
): Promise<ClaudeResponse> {
  // The user's prompt IS the system/user instruction they've crafted.
  // We wrap it with the task so Claude knows what to answer.
  return callClaude(
    apiKey,
    [{ role: 'user', content: `${userPrompt}\n\n【課題】\n${task}` }],
    undefined,
    512,
  );
}

// ── DOJO: evaluate quality of response ───────────────────────────────────────

export async function evaluateResponse(
  apiKey: string,
  task: string,
  response: string,
  criteria: string,
): Promise<EvalResult> {
  const evalPrompt = `あなたは厳格な採点者です。以下の課題に対する回答を評価してください。

【課題】
${task}

【回答】
${response}

【採点基準】
${criteria}

以下のJSON形式のみで返してください（説明文不要）:
{"score": <0-100の整数>, "feedback": "<日本語で1文の採点理由>"}`;

  const result = await callClaude(
    apiKey,
    [{ role: 'user', content: evalPrompt }],
    undefined,
    200,
  );

  try {
    const cleaned = result.content.replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim();
    const parsed = JSON.parse(cleaned) as { score: number; feedback: string };
    return { qualityScore: Math.max(0, Math.min(100, parsed.score)), feedback: parsed.feedback };
  } catch {
    return { qualityScore: 50, feedback: '採点結果を解析できませんでした' };
  }
}

// ── BUILDER: evaluate session deliverables ────────────────────────────────────

export async function evaluateBuilderSession(
  apiKey: string,
  challengeTitle: string,
  requirements: string[],
  sessionGoal: string,
  userSubmission: string,
): Promise<EvalResult> {
  const reqList = requirements.map((r, i) => `${i + 1}. ${r}`).join('\n');
  const evalPrompt = `あなたはシニアエンジニアとしてコードレビューを行います。

【チャレンジ】${challengeTitle}
【全要件】
${reqList}

【今セッションのゴール】${sessionGoal}

【提出内容・説明】
${userSubmission}

今セッションのゴールに対する達成度を以下のJSON形式のみで評価してください:
{"score": <0-100の整数>, "feedback": "<日本語で2文以内の評価コメント>"}`;

  const result = await callClaude(apiKey, [{ role: 'user', content: evalPrompt }], undefined, 300);
  try {
    const cleaned = result.content.replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim();
    const parsed = JSON.parse(cleaned) as { score: number; feedback: string };
    return { qualityScore: Math.max(0, Math.min(100, parsed.score)), feedback: parsed.feedback };
  } catch {
    return { qualityScore: 60, feedback: 'セッション評価を解析できませんでした' };
  }
}

// ── Estimate token count (rough: 1 token ≈ 4 chars for Japanese) ─────────────

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 2.5);
}
