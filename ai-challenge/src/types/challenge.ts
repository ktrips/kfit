// ── Stage & Difficulty ───────────────────────────────────────────────────────

export type Stage = 'dojo' | 'builder' | 'creator';
export type Difficulty = 'easy' | 'normal' | 'hard' | 'expert' | 'master';
export type Medal = 'gold' | 'silver' | 'bronze' | 'none';

// ── DOJO ─────────────────────────────────────────────────────────────────────

export interface DojoChallenge {
  day: number;
  skill: string;
  theme: string;
  description: string;
  task: string;                 // The prompt task to complete
  targetOutput: string;         // What a perfect response looks like
  hints: string[];
  tokenLimits: {
    gold: number;               // ≤ this = gold medal
    silver: number;
    bronze: number;
  };
  evaluationCriteria: string;   // Instructions for Claude self-evaluation
}

// ── BUILDER ───────────────────────────────────────────────────────────────────

export interface BuilderChallenge {
  id: string;
  title: string;
  difficulty: Difficulty;
  difficultyStars: number;      // 1-5
  description: string;
  requirements: string[];       // Checklist of what the app must do
  techStack: string[];
  estimatedSessions: number;    // How many 5h sessions expected
  baseTokenBudget: number;      // Total token budget across all sessions
  sessionBreakdown: SessionPlan[];
  unlockCondition?: string;     // e.g. "Complete all HARD challenges"
}

export interface SessionPlan {
  session: number;
  goal: string;
  deliverables: string[];
}

// ── User Progress ─────────────────────────────────────────────────────────────

export interface DojoDayProgress {
  day: number;
  completed: boolean;
  medal: Medal;
  tokensUsed: number;
  score: number;
  attempts: number;
  completedAt?: string;
}

export interface BuilderChallengeProgress {
  challengeId: string;
  started: boolean;
  completed: boolean;
  currentSession: number;
  totalTokensUsed: number;
  score: number;
  sessionsData: SessionProgress[];
  startedAt?: string;
  completedAt?: string;
}

export interface SessionProgress {
  session: number;
  completed: boolean;
  tokensUsed: number;
  completedAt?: string;
}

// ── Attempt / Result ──────────────────────────────────────────────────────────

export interface ChallengeAttempt {
  prompt: string;
  response: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  qualityScore: number;         // 0-100 from Claude self-eval
  score: number;                // Final game score
  medal: Medal;
  timestamp: string;
}

// ── Usage Windows ─────────────────────────────────────────────────────────────

export interface SprintUsage {
  windowStart: string;          // ISO timestamp
  windowEnd: string;            // windowStart + 5h
  tokensUsed: number;
  tokensLimit: number;          // 50,000 default
}

export interface WeeklyUsage {
  weekStart: string;            // ISO timestamp (Monday)
  tokensUsed: number;
  tokensLimit: number;          // 200,000 default
  sprintsCompleted: number;
  totalScore: number;
}

// ── Leaderboard ────────────────────────────────────────────────────────────────

export interface LeaderboardEntry {
  uid: string;
  username: string;
  weeklyScore: number;
  weeklyTokens: number;
  dojoComplete: boolean;
  rank: number;
}

// ── Game State ────────────────────────────────────────────────────────────────

export interface GameProgress {
  uid: string;
  stage: Stage;
  dojoProgress: DojoDayProgress[];
  builderProgress: BuilderChallengeProgress[];
  totalScore: number;
  streak: number;
  lastActiveDate: string;
  sprint: SprintUsage;
  weekly: WeeklyUsage;
  achievements: Achievement[];
}

export interface Achievement {
  id: string;
  name: string;
  description: string;
  icon: string;
  earnedAt: string;
}

// ── Score Calculation ─────────────────────────────────────────────────────────

export function calcDojoScore(
  qualityScore: number,
  tokensUsed: number,
  tokenLimit: number,
  attempts: number,
): { score: number; medal: Medal } {
  const efficiency = Math.min(tokenLimit / Math.max(tokensUsed, 1), 1);
  const attemptPenalty = Math.max(0, (attempts - 1) * 0.1);
  const raw = Math.floor((qualityScore / 100) * efficiency * 1000 * (1 - attemptPenalty));
  const score = Math.max(0, raw);

  let medal: Medal = 'none';
  if (score >= 800 && attempts === 1) medal = 'gold';
  else if (score >= 500) medal = 'silver';
  else if (score >= 250) medal = 'bronze';

  return { score, medal };
}

export function calcBuilderScore(
  qualityScore: number,
  tokensUsed: number,
  baseTokenBudget: number,
  sessionsUsed: number,
  estimatedSessions: number,
  difficultyStars: number,
): number {
  const tokenEff = Math.min(baseTokenBudget / Math.max(tokensUsed, 1), 1);
  const timeBonus = sessionsUsed < estimatedSessions ? 1.5 : sessionsUsed === estimatedSessions ? 1.0 : 0.7;
  return Math.floor((qualityScore / 100) * tokenEff * 500 * timeBonus * difficultyStars);
}
