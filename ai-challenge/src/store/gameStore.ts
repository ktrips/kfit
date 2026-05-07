import { create } from 'zustand';
import type { User } from 'firebase/auth';
import type {
  Stage,
  DojoDayProgress,
  BuilderChallengeProgress,
  SprintUsage,
  WeeklyUsage,
  Achievement,
  ChallengeAttempt,
  Medal,
} from '../types/challenge';

const SPRINT_HOURS = 5;
const SPRINT_TOKEN_LIMIT = 50_000;
const WEEKLY_TOKEN_LIMIT = 200_000;

function getWeekStart(): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - d.getDay() + 1); // Monday
  return d.toISOString();
}

function newSprint(): SprintUsage {
  const now = new Date();
  const end = new Date(now.getTime() + SPRINT_HOURS * 3600 * 1000);
  return {
    windowStart: now.toISOString(),
    windowEnd: end.toISOString(),
    tokensUsed: 0,
    tokensLimit: SPRINT_TOKEN_LIMIT,
  };
}

function newWeekly(): WeeklyUsage {
  return {
    weekStart: getWeekStart(),
    tokensUsed: 0,
    tokensLimit: WEEKLY_TOKEN_LIMIT,
    sprintsCompleted: 0,
    totalScore: 0,
  };
}

export type View =
  | 'login'
  | 'map'
  | 'dojo'
  | 'builder'
  | 'results'
  | 'leaderboard'
  | 'settings';

interface GameState {
  // Auth
  user: User | null;
  apiKey: string;                     // Anthropic API key (localStorage)
  setUser: (u: User | null) => void;
  setApiKey: (key: string) => void;

  // Navigation
  view: View;
  selectedDojoDay: number | null;
  selectedBuilderId: string | null;
  lastAttempt: ChallengeAttempt | null;
  setView: (v: View) => void;
  goToDojo: (day: number) => void;
  goToBuilder: (id: string) => void;
  setLastAttempt: (a: ChallengeAttempt | null) => void;

  // Progress
  stage: Stage;
  dojoProgress: DojoDayProgress[];
  builderProgress: BuilderChallengeProgress[];
  totalScore: number;
  streak: number;
  achievements: Achievement[];

  // Usage windows
  sprint: SprintUsage;
  weekly: WeeklyUsage;

  // Actions
  recordDojoAttempt: (day: number, attempt: ChallengeAttempt) => void;
  recordBuilderSession: (challengeId: string, session: number, tokensUsed: number) => void;
  completeBuilderChallenge: (challengeId: string, score: number) => void;
  addTokens: (count: number) => void;
  resetSprintIfExpired: () => void;
  resetWeeklyIfExpired: () => void;
  unlockStage: (stage: Stage) => void;
}

const STORAGE_KEY = 'ailingo.apiKey';

export const useGameStore = create<GameState>((set, get) => ({
  // ── Auth ──────────────────────────────────────────────────────────────────
  user: null,
  apiKey: localStorage.getItem(STORAGE_KEY) ?? '',
  setUser: (user) => set({ user, view: user ? 'map' : 'login' }),
  setApiKey: (apiKey) => {
    localStorage.setItem(STORAGE_KEY, apiKey);
    set({ apiKey });
  },

  // ── Navigation ────────────────────────────────────────────────────────────
  view: 'login',
  selectedDojoDay: null,
  selectedBuilderId: null,
  lastAttempt: null,
  setView: (view) => set({ view }),
  goToDojo: (day) => set({ selectedDojoDay: day, view: 'dojo' }),
  goToBuilder: (id) => set({ selectedBuilderId: id, view: 'builder' }),
  setLastAttempt: (lastAttempt) => set({ lastAttempt }),

  // ── Progress ──────────────────────────────────────────────────────────────
  stage: 'dojo',
  dojoProgress: Array.from({ length: 7 }, (_, i) => ({
    day: i + 1,
    completed: false,
    medal: 'none' as Medal,
    tokensUsed: 0,
    score: 0,
    attempts: 0,
  })),
  builderProgress: [],
  totalScore: 0,
  streak: 0,
  achievements: [],

  // ── Usage ──────────────────────────────────────────────────────────────────
  sprint: newSprint(),
  weekly: newWeekly(),

  // ── Actions ───────────────────────────────────────────────────────────────
  recordDojoAttempt: (day, attempt) => {
    const { dojoProgress, totalScore } = get();
    const idx = dojoProgress.findIndex((d) => d.day === day);
    if (idx < 0) return;
    const prev = dojoProgress[idx];
    const alreadyCompleted = prev.completed;

    const updated = dojoProgress.map((d) =>
      d.day === day
        ? {
            ...d,
            completed: true,
            medal: attempt.medal,
            tokensUsed: attempt.totalTokens,
            score: Math.max(d.score, attempt.score),
            attempts: d.attempts + 1,
            completedAt: new Date().toISOString(),
          }
        : d,
    );

    const scoreGain = alreadyCompleted ? 0 : attempt.score;

    // Check if DOJO complete → unlock BUILDER
    const allDone = updated.every((d) => d.completed);

    set({
      dojoProgress: updated,
      totalScore: totalScore + scoreGain,
      stage: allDone ? 'builder' : get().stage,
    });
    get().addTokens(attempt.totalTokens);
  },

  recordBuilderSession: (challengeId, session, tokensUsed) => {
    const { builderProgress } = get();
    const existing = builderProgress.find((b) => b.challengeId === challengeId);
    if (existing) {
      const updated = builderProgress.map((b) =>
        b.challengeId === challengeId
          ? {
              ...b,
              currentSession: session + 1,
              totalTokensUsed: b.totalTokensUsed + tokensUsed,
              sessionsData: [
                ...b.sessionsData,
                { session, completed: true, tokensUsed, completedAt: new Date().toISOString() },
              ],
            }
          : b,
      );
      set({ builderProgress: updated });
    } else {
      set({
        builderProgress: [
          ...builderProgress,
          {
            challengeId,
            started: true,
            completed: false,
            currentSession: session + 1,
            totalTokensUsed: tokensUsed,
            score: 0,
            sessionsData: [{ session, completed: true, tokensUsed, completedAt: new Date().toISOString() }],
            startedAt: new Date().toISOString(),
          },
        ],
      });
    }
    get().addTokens(tokensUsed);
  },

  completeBuilderChallenge: (challengeId, score) => {
    const { builderProgress, totalScore } = get();
    const updated = builderProgress.map((b) =>
      b.challengeId === challengeId
        ? { ...b, completed: true, score, completedAt: new Date().toISOString() }
        : b,
    );
    set({ builderProgress: updated, totalScore: totalScore + score });
  },

  addTokens: (count) => {
    const { sprint, weekly } = get();
    set({
      sprint: { ...sprint, tokensUsed: sprint.tokensUsed + count },
      weekly: { ...weekly, tokensUsed: weekly.tokensUsed + count },
    });
  },

  resetSprintIfExpired: () => {
    const { sprint } = get();
    if (new Date() > new Date(sprint.windowEnd)) {
      set({ sprint: newSprint() });
    }
  },

  resetWeeklyIfExpired: () => {
    const { weekly } = get();
    const currentWeekStart = getWeekStart();
    if (weekly.weekStart !== currentWeekStart) {
      set({ weekly: newWeekly() });
    }
  },

  unlockStage: (stage) => set({ stage }),
}));
