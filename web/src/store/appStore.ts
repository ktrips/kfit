import { create } from 'zustand';
import { User } from 'firebase/auth';

interface Exercise {
  id: string;
  name: string;
  basePoints: number;
  difficulty: string;
  muscleGroups: string[];
}

interface UserProfile {
  uid: string;
  email: string;
  username: string;
  totalPoints: number;
  streak: number;
  joinDate: Date;
  lastActiveDate: Date;
}

interface AppState {
  user: User | null;
  userProfile: UserProfile | null;
  exercises: Exercise[];
  isLoading: boolean;
  error: string | null;
  setUser: (user: User | null) => void;
  setUserProfile: (profile: UserProfile | null) => void;
  setExercises: (exercises: Exercise[]) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  updateUserPoints: (points: number) => void;
  incrementStreak: () => void;
  resetStreak: () => void;
}

export const useAppStore = create<AppState>((set) => ({
  user: null,
  userProfile: null,
  exercises: [],
  isLoading: false,
  error: null,

  setUser: (user) => set({ user }),
  setUserProfile: (profile) => set({ userProfile: profile }),
  setExercises: (exercises) => set({ exercises }),
  setLoading: (loading) => set({ isLoading: loading }),
  setError: (error) => set({ error }),

  updateUserPoints: (points) => set((state) => ({
    userProfile: state.userProfile
      ? { ...state.userProfile, totalPoints: state.userProfile.totalPoints + points }
      : null,
  })),

  incrementStreak: () => set((state) => ({
    userProfile: state.userProfile
      ? { ...state.userProfile, streak: state.userProfile.streak + 1 }
      : null,
  })),

  resetStreak: () => set((state) => ({
    userProfile: state.userProfile
      ? { ...state.userProfile, streak: 0 }
      : null,
  })),
}));
