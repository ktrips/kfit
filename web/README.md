# kfit Web App (v0.4.13)

A React-based web application for tracking fitness habits with Duolingo-like gamification.

## Features

- **Google Authentication** - Sign in with Google
- **Exercise Tracking** - Manual rep counting for push-ups, squats, sit-ups, lunges, planks, burpees
- **AI Training Plans** - Generate personalized workout plans
- **Weekly Goals** - Set and track weekly exercise targets
- **History View** - Review past 14 days of workouts
- **Daily Dashboard** - View today's workouts, points, and streaks
- **XP System** - Earn points based on reps and exercise type
- **Streak Tracking** - Build consecutive day streaks
- **Real-time Sync** - Firestore backend syncs with iOS/Watch apps

## Tech Stack

- **React 18** - UI framework
- **TypeScript** - Type safety
- **Vite** - Build tool
- **Firebase** - Authentication & Firestore database
- **Zustand** - State management
- **Tailwind CSS** - Styling
- **Lucide React** - Icons

## Setup

1. **Install dependencies**
   ```bash
   npm install
   ```

2. **Configure Firebase**
   - Copy `.env.example` to `.env.local`
   - Add your Firebase project credentials from Firebase Console

3. **Start development server**
   ```bash
   npm run dev
   ```

4. **Build for production**
   ```bash
   npm run build
   ```

## Project Structure

```
src/
├── components/          # React components
│   ├── LoginView.tsx
│   ├── DashboardView.tsx
│   ├── ExerciseTrackerView.tsx
│   ├── WeeklyGoalView.tsx
│   ├── HistoryView.tsx
│   ├── HelpView.tsx
│   └── WorkoutPlanView.tsx
├── services/
│   └── firebase.ts      # Firebase SDK wrapper
├── store/
│   └── appStore.ts      # Zustand state management
├── App.tsx              # Main app component
├── main.tsx             # Entry point
└── index.css            # Tailwind styles
```

## Environment Variables

```
VITE_FIREBASE_API_KEY
VITE_FIREBASE_AUTH_DOMAIN
VITE_FIREBASE_PROJECT_ID
VITE_FIREBASE_STORAGE_BUCKET
VITE_FIREBASE_MESSAGING_SENDER_ID
VITE_FIREBASE_APP_ID
```

## Development Commands

- `npm run dev` - Start dev server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run linter
- `npm run type-check` - Run TypeScript type checker

## Firebase Setup

See `../firebase/SETUP.md` for detailed Firebase setup instructions including:
- Creating Firestore database
- Deploying security rules
- Setting up Cloud Functions
- Configuring Google Authentication

## Recent Updates (v0.4.x)

- ✅ AI Training Plan generation
- ✅ Weekly Goals view
- ✅ History view (past 14 days)
- ✅ Help/FAQ view
- ✅ Real-time sync with iOS and Apple Watch
- ✅ Enhanced XP system with multiple exercise types
- ✅ Client-side streak and points calculation

## Version

Current version: **0.4.13** (May 2026)
