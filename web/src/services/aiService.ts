// ── AI プロバイダー設定 ────────────────────────────────────────────────────────

export type AIProvider = 'openai' | 'gemini' | 'anthropic';

export interface AISettings {
  provider: AIProvider;
  apiKey: string;
  /** OpenAI: gpt-4o / gpt-4o-mini, Gemini: gemini-2.0-flash, Anthropic: claude-3-5-haiku */
  model?: string;
}

const STORAGE_KEY = 'kfit.aiSettings';

export function getAISettings(): AISettings | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as AISettings) : null;
  } catch {
    return null;
  }
}

export function saveAISettings(settings: AISettings): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
}

export function clearAISettings(): void {
  localStorage.removeItem(STORAGE_KEY);
}

// ── デフォルトモデル ───────────────────────────────────────────────────────────

export const DEFAULT_MODELS: Record<AIProvider, string> = {
  openai:    'gpt-4o-mini',
  gemini:    'gemini-2.0-flash',
  anthropic: 'claude-3-5-haiku-20241022',
};

export const PROVIDER_LABELS: Record<AIProvider, string> = {
  openai:    'OpenAI (ChatGPT)',
  gemini:    'Google Gemini',
  anthropic: 'Anthropic (Claude)',
};

// ── 生成されたプランの型 ────────────────────────────────────────────────────────

export interface PlanExercise {
  name: string;
  sets: number;
  reps: string;
  rest: string;
  tip?: string;
}

export interface WeekDayPlan {
  day: string;
  focus: string;
  exercises: PlanExercise[];
  cardio?: string;
  estimatedTime?: string;
}

export interface ProgressMilestone {
  week: number;
  milestone: string;
}

export interface AIGeneratedPlan {
  id: string;
  createdAt: string;
  goal: string;
  daysPerWeek: number;
  deadline: string;
  fitnessLevel: string;
  provider: AIProvider;
  title: string;
  summary: string;
  weeklySchedule: WeekDayPlan[];
  nutritionTips: string[];
  progressMilestones: ProgressMilestone[];
  restDays?: string;
}

// ── プロンプト構築 ─────────────────────────────────────────────────────────────

function buildPrompt(
  goal: string,
  daysPerWeek: number,
  deadline: string,
  fitnessLevel: string
): string {
  return `あなたは一流のパーソナルトレーナーです。以下の情報をもとに、実現可能で科学的根拠のある自重トレーニングプランを日本語で作成してください。

【目標】${goal}
【週のトレーニング日数】${daysPerWeek}日
【達成期限】${deadline}
【現在の体力レベル】${fitnessLevel}

以下のJSON形式のみで返答してください（余分な説明文は不要）:
{
  "title": "プランタイトル（20字以内）",
  "summary": "このプランの概要（2〜3文、なぜこのプランが目標達成に効果的か）",
  "weeklySchedule": [
    {
      "day": "月曜日",
      "focus": "部位・目的（例: 下半身・心肺機能）",
      "exercises": [
        {
          "name": "種目名",
          "sets": 3,
          "reps": "20回",
          "rest": "60秒",
          "tip": "フォームの要点"
        }
      ],
      "cardio": "有酸素運動（任意、例: 20分ウォーキング）",
      "estimatedTime": "所要時間（例: 30分）"
    }
  ],
  "nutritionTips": [
    "栄養アドバイス1",
    "栄養アドバイス2"
  ],
  "progressMilestones": [
    { "week": 2, "milestone": "マイルストーン" }
  ],
  "restDays": "休息日の過ごし方（例: 火・木は軽いストレッチのみ）"
}`;
}

// ── API 呼び出し ───────────────────────────────────────────────────────────────

async function callOpenAI(apiKey: string, model: string, prompt: string): Promise<string> {
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      response_format: { type: 'json_object' },
      temperature: 0.7,
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as any)?.error?.message ?? `OpenAI API error ${res.status}`);
  }
  const data = await res.json();
  return data.choices[0].message.content as string;
}

async function callGemini(apiKey: string, model: string, prompt: string): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: 'application/json', temperature: 0.7 },
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as any)?.error?.message ?? `Gemini API error ${res.status}`);
  }
  const data = await res.json();
  return data.candidates[0].content.parts[0].text as string;
}

async function callAnthropic(apiKey: string, model: string, prompt: string): Promise<string> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }],
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    const msg = (err as any)?.error?.message ?? `Anthropic API error ${res.status}`;
    if (res.status === 0 || msg.toLowerCase().includes('cors')) {
      throw new Error(
        'Anthropic APIはブラウザから直接呼び出せない場合があります。OpenAI か Gemini をお試しください。'
      );
    }
    throw new Error(msg);
  }
  const data = await res.json();
  return data.content[0].text as string;
}

// ── メイン生成関数 ─────────────────────────────────────────────────────────────

export async function generateWorkoutPlan(
  settings: AISettings,
  goal: string,
  daysPerWeek: number,
  deadline: string,
  fitnessLevel: string
): Promise<AIGeneratedPlan> {
  const model = settings.model ?? DEFAULT_MODELS[settings.provider];
  const prompt = buildPrompt(goal, daysPerWeek, deadline, fitnessLevel);

  let rawJson: string;
  switch (settings.provider) {
    case 'openai':
      rawJson = await callOpenAI(settings.apiKey, model, prompt);
      break;
    case 'gemini':
      rawJson = await callGemini(settings.apiKey, model, prompt);
      break;
    case 'anthropic':
      rawJson = await callAnthropic(settings.apiKey, model, prompt);
      break;
  }

  // JSON をパース（コードブロック付きで返ってくる場合も除去）
  const cleaned = rawJson.replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim();
  const parsed = JSON.parse(cleaned);

  return {
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    goal,
    daysPerWeek,
    deadline,
    fitnessLevel,
    provider: settings.provider,
    title:      parsed.title              ?? 'AIプラン',
    summary:    parsed.summary            ?? '',
    weeklySchedule:      parsed.weeklySchedule      ?? [],
    nutritionTips:       parsed.nutritionTips        ?? [],
    progressMilestones:  parsed.progressMilestones   ?? [],
    restDays:            parsed.restDays,
  };
}

// ── 生成プランのローカル保存 ───────────────────────────────────────────────────

const PLANS_KEY = 'kfit.aiPlans';

export function getSavedPlans(): AIGeneratedPlan[] {
  try {
    return JSON.parse(localStorage.getItem(PLANS_KEY) ?? '[]') as AIGeneratedPlan[];
  } catch {
    return [];
  }
}

export function savePlan(plan: AIGeneratedPlan): void {
  const plans = getSavedPlans();
  // 同一 ID は上書き、新規は先頭に追加
  const idx = plans.findIndex(p => p.id === plan.id);
  if (idx >= 0) plans[idx] = plan;
  else plans.unshift(plan);
  localStorage.setItem(PLANS_KEY, JSON.stringify(plans));
}

export function deletePlan(id: string): void {
  const plans = getSavedPlans().filter(p => p.id !== id);
  localStorage.setItem(PLANS_KEY, JSON.stringify(plans));
}
