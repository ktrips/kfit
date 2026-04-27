# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commit & Push Workflow

**IMPORTANT**: Before running `git commit` and `git push`, always:
1. Show the list of changed files (`git status` and `git diff --stat`)
2. Show the proposed commit message
3. Ask the user for confirmation before proceeding

Do not commit or push without explicit user approval.

## Project Overview

**kfit** - A Duolingo-like habit-building app for home exercise tracking across iOS and Web platforms. Uses iPhone motion sensors (Core Motion) to count reps for push-ups, squats, and sit-ups. Features gamification (points, streaks, achievements, leaderboards) backed by Firebase/Firestore.

**Tech Stack:**
- **Backend**: Firebase + Firestore (real-time database)
- **iOS**: SwiftUI + Core Motion (CMMotionManager for accelerometer/gyroscope)
- **Web**: React 18 + TypeScript + Vite + Tailwind CSS
- **State Management**: Zustand (lightweight) or Redux Toolkit
- **Form Validation**: React Hook Form + Zod
- **UI Components**: shadcn/ui
- **Storage**: Firestore (primary) + IndexedDB (web cache) + Core Data (iOS offline queue)

## Project Structure

```
kfit/
├── firebase/                    # Firebase backend setup
│   ├── firestore.rules         # Security rules
│   ├── firebase-config.ts      # Firebase initialization
│   └── functions/              # Cloud Functions
│       ├── calculatePoints.js  # Points aggregation
│       ├── updateStreak.js     # Streak logic
│       └── checkAchievements.js# Achievement unlocking
├── web/
│   ├── src/
│   │   ├── components/
│   │   │   ├── auth/           # Google login flow
│   │   │   ├── dashboard/      # Daily goals view
│   │   │   ├── exercises/      # Exercise tracking UI
│   │   │   ├── achievements/   # Badge display
│   │   │   └── leaderboard/    # Rankings
│   │   ├── services/
│   │   │   ├── firebase.ts     # Firestore SDK wrapper
│   │   │   ├── sync.ts         # Real-time listeners
│   │   │   └── analytics.ts    # Points/metrics calculation
│   │   ├── hooks/
│   │   │   ├── useAuth.ts
│   │   │   ├── useExercises.ts
│   │   │   ├── useGoals.ts
│   │   │   └── useSyncEngine.ts
│   │   ├── store/              # Zustand store
│   │   ├── types/              # TypeScript interfaces
│   │   └── main.tsx
│   ├── .env.example
│   ├── vite.config.ts
│   └── package.json
└── ios/
    ├── FitnessApp.xcodeproj
    ├── FitnessApp/
    │   ├── Models/
    │   │   ├── User.swift
    │   │   ├── Exercise.swift
    │   │   ├── DailyGoal.swift
    │   │   └── Achievement.swift
    │   ├── ViewModels/
    │   │   ├── AuthViewModel.swift
    │   │   ├── ExerciseViewModel.swift
    │   │   ├── GoalsViewModel.swift
    │   │   └── SyncViewModel.swift
    │   ├── Views/
    │   │   ├── Auth/
    │   │   ├── Dashboard/
    │   │   ├── Exercises/
    │   │   ├── Achievements/
    │   │   └── Leaderboard/
    │   ├── Services/
    │   │   ├── FirebaseService.swift
    │   │   ├── MotionDetectionService.swift  # Core Motion integration
    │   │   ├── ExerciseAnalyzer.swift       # Form scoring
    │   │   └── SyncEngine.swift
    │   └── App/
    │       └── FitnessApp.swift
    └── Podfile
```

## Core Architecture

### 1. Firestore Data Model

**Collections:**
```
users/{userId}/
├── profile                    # User metadata, totalPoints, streak
├── daily-goals/              # Daily targets per exercise
├── completed-exercises/      # Workout logs with timestamps
├── three-month-goals/        # Long-term progress tracking
├── achievements/             # Earned badges
└── statistics/               # Aggregated metrics

exercises/                    # Global exercise definitions (read-only)
leaderboards/{period}/        # Weekly/monthly rankings
```

**Key Document Structure:**
- `users/{userId}/profile`: { username, email, totalPoints, streak, lastActiveDate, preferences }
- `users/{userId}/completed-exercises`: { exerciseId, reps, sets, timestamp, formScore, caloriesBurned }
- `users/{userId}/achievements`: { achievementId, earnedDate, name, tier }

### 2. Motion Detection (iOS)

**Core Flow:**
1. User selects exercise type (push-up/squat/sit-up)
2. System establishes baseline acceleration during 2-sec calibration
3. CMMotionManager monitors accelerometer + gyroscope at 50Hz
4. Detects rep completion via peak detection in acceleration magnitude
5. Form score calculated from motion smoothness (jerk analysis)
6. Results saved to Firestore with timestamp + form metadata

**Exercise-Specific Profiles:**
- **Push-ups**: Vertical Z-axis acceleration (down + up cycle = 1 rep)
- **Squats**: Vertical acceleration + gyro Y-axis stability during hold
- **Sit-ups**: X-axis acceleration + gyro rotation consistency

See `ios/FitnessApp/Services/MotionDetectionService.swift` for implementation.

### 3. Real-time Sync Engine

**Write Path:** iOS/Web exercise → Firestore document write → Cloud Function triggers → Updates points/streak/achievements → Firestore listener on other platform detects change → UI updates

**Sync Strategy:**
- Firestore `onSnapshot()` listeners for real-time updates
- IndexedDB cache (web) + Core Data queue (iOS) for offline support
- Last-Write-Wins conflict resolution with timestamp validation
- Debounced writes to prevent Firestore throttling

### 4. Gamification Engine

**Points System:**
- Base: Push-up/Sit-up = 10 pts, Squat = 15 pts per rep
- Form bonus: +10% (perfect form)
- Streak bonus: +5% per consecutive day (max 50%)
- Daily goal completion: +100 bonus
- First exercise of day: +20%

**Streak Logic:**
- Tracks consecutive days with any exercise
- Lost if no activity >24 hours
- Cloud Function runs daily to update streaks

**Achievements (Sample):**
- Early Bird (10 workouts before 9 AM)
- Form Master (50 perfect-form exercises)
- Iron Will (30-day streak)
- Century Club (100+ reps in one day)
- Leaderboard King (#1 weekly rank)

See Cloud Functions in `firebase/functions/` for achievement evaluation logic.

### 5. Leaderboard

**Weekly Aggregation:**
- Cloud Function runs Sundays 11:59 PM UTC
- Aggregates points earned Mon-Sun per user
- Generates top 100 global rankings
- Awards bonus points to top 10
- Updates `leaderboards/week-YYYY-WW/entries` collection

## Development Workflow

### Setup

**Prerequisites:**
- Node.js 18+
- Xcode 14+ (iOS development)
- Firebase CLI
- Git

**Initial Setup:**
```bash
# Clone repo
git clone <repo-url>
cd fitness-app

# Firebase setup
firebase login
firebase init (if not already configured)

# Web setup
cd web
npm install
cp .env.example .env.local
# Add Firebase config to .env.local

# iOS setup
cd ../ios
pod install
# Open FitnessApp.xcworkspace in Xcode
```

### Building & Running

**Web Development:**
```bash
cd web
npm run dev              # Start Vite dev server (http://localhost:5173)
npm run build           # Production build
npm run preview         # Preview production build
npm run lint            # ESLint check
npm run type-check      # TypeScript check
```

**iOS Development:**
```bash
cd ios
open FitnessApp.xcworkspace
# In Xcode: Product → Scheme → FitnessApp → Run
# Or: Cmd+R to build and run on simulator
```

**Firebase Functions (Local Testing):**
```bash
cd firebase/functions
npm install
npm run build
firebase emulator:start # Runs local emulator
```

### Testing

**Web Tests:**
```bash
cd web
npm run test            # Jest tests
npm run test:watch     # Watch mode
npm run test:coverage  # Coverage report
```

**iOS Tests:**
```bash
cd ios
# In Xcode: Product → Test (Cmd+U)
# Or run specific test: Product → Test Plan
```

### Code Style & Quality

**Web:**
- ESLint: `npm run lint`
- Format: Prettier (auto on save with pre-commit hook)
- Type checking: `npm run type-check`

**iOS:**
- SwiftLint: `swiftlint` (configured in `ios/.swiftlint.yml`)
- Format: Xcode native formatting

## Critical Implementation Details

### Motion Detection Algorithm

**Push-up Detection (simplified):**
```
1. Baseline = average acceleration during 2-sec calibration
2. Monitor real-time acceleration magnitude
3. When magnitude > baseline + threshold:
   - If negative Z-axis: rep_phase = "down"
   - If positive Z-axis (after down): rep_phase = "up"
   - When both phases detected: increment rep counter
4. Form score = 1 - (motion_jerk / max_jerk) * 100
```

See `ios/FitnessApp/Services/ExerciseAnalyzer.swift` for complete algorithm.

### Firestore Security Rules

**Key Principles:**
- Users can only read/write own data
- Exercises collection is globally readable
- Leaderboards are publicly readable
- Cloud Functions have elevated privileges (runs as admin)

```firestore
match /users/{userId} {
  allow read, write: if request.auth.uid == userId;
}
match /exercises {
  allow read: if true;
}
match /leaderboards/{document=**} {
  allow read: if true;
}
```

### Cross-Platform Sync Logic

**Conflict Resolution (Last-Write-Wins):**
When same document modified on both iOS and Web:
1. Firestore stores the write with latest server timestamp
2. Both clients receive update via listener
3. If data discrepancy > 10% (e.g., reps differ significantly):
   - Flag entry for manual review in admin console
   - Log to analytics for analysis
4. Validate rep count against motion data + form scores on server

## Common Commands

| Task | Command |
|------|---------|
| Start web dev server | `cd web && npm run dev` |
| Build web for production | `cd web && npm run build` |
| Run web tests | `cd web && npm run test:watch` |
| Deploy to Firebase Hosting | `firebase deploy --only hosting` |
| Deploy Cloud Functions | `firebase deploy --only functions` |
| Deploy Firestore rules | `firebase deploy --only firestore:rules` |
| Open Firestore console | `firebase open firestore` |
| View Firebase logs | `firebase functions:log` |
| Run iOS app in simulator | Open Xcode, Cmd+R |
| Run iOS tests | Xcode: Product → Test (Cmd+U) |

## Key Decisions & Rationale

1. **iOS First**: Motion sensor (Core Motion) is iOS-specific; provides core value. Web uses manual input initially.
2. **Firestore as Source of Truth**: Simplifies architecture, enables real-time sync, leverages existing infrastructure.
3. **Weekly (not real-time) Leaderboards**: Prevents gaming via scheduled Cloud Function. Reduces compute cost.
4. **Offline-First on iOS**: Users exercise in areas with spotty WiFi. Local Core Data queue + sync when online.
5. **Manual Counter with Motion Validation**: Motion unreliable for all body types/forms. Manual ensures accuracy; motion adds gamification.

## Debugging Tips

**iOS Motion Detection Not Triggering:**
- Check `MotionDetectionService.swift` baseline calibration
- Verify CMMotionManager `isAccelerometerAvailable` on device
- Test with simulator: Motion → Device Orientation changes (limited in simulator)
- Check console logs for motion threshold mismatches

**Firestore Sync Delays:**
- Check network connectivity
- Verify Firestore rules allow read/write
- Monitor Firebase console for write conflicts
- Check `SyncEngine.ts` debounce settings

**Points Not Updating:**
- Verify Cloud Function deployed: `firebase functions:list`
- Check function logs: `firebase functions:log`
- Ensure Firestore trigger paths match collection structure
- Test locally with emulator: `firebase emulator:start`

## References

- [Firebase Firestore Docs](https://firebase.google.com/docs/firestore)
- [Core Motion Developer Docs](https://developer.apple.com/documentation/coremotion)
- [React Firebase Hooks](https://react-firebase-hooks.com/)
- [SwiftUI State Management](https://developer.apple.com/tutorials/swiftui)
- [Vite Documentation](https://vitejs.dev/)
