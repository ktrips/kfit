# kfit - Duolingo-Like Fitness Habit App

Build fitness habits just like Duolingo. Track push-ups, squats, and sit-ups with motion sensor rep counting across Web, iOS, and Apple Watch apps.

## 🎯 Features

- **Motion Sensor Rep Counting** - iPhone and Apple Watch accelerometer/gyroscope detection
- **Real-time Form Scoring** - Gyro-based movement quality analysis (0-100%)
- **Daily Dashboard** - Streaks, points, workout history at a glance
- **3-Month Goal Tracking** - Build consistent fitness habits over time
- **Gamification** - Points system, achievements, weekly leaderboards
- **Cross-Platform Sync** - Web, iOS, and Watch apps stay in sync via Firebase
- **Offline Support** - Local caching on iOS/Watch, works without connectivity
- **Haptic Feedback** - Real-time vibration on rep completion

## 📱 Platforms

### Web App (React + TypeScript)
- Google authentication
- Manual rep counter
- Real-time dashboard
- Exercise logging

### iOS App (SwiftUI)
- Google Sign-in
- Core Motion rep detection (50 Hz)
- Form scoring with haptic feedback
- Dashboard with stats
- Firebase Firestore sync

### Apple Watch App (WatchKit)
- Motion sensor rep counting (20 Hz, battery optimized)
- Gyroscope form analysis
- Quick workout logging
- Auto-calibration
- Watch Connectivity sync with iPhone

## 🚀 Quick Start

### Run Web App Locally

```bash
cd web
npm install
npm run dev
```

Access at: **http://localhost:5173/**

### Run iOS App

```bash
cd ios
pod install
open kfit.xcworkspace
# Select device/simulator → Cmd+R
```

### Run Apple Watch App

```bash
cd ios
pod install
open kfit.xcworkspace
# Select kfitWatch scheme → Cmd+R
```

## 📋 Tech Stack

### Frontend
- **Web**: React 18, TypeScript, Vite, Tailwind CSS
- **iOS**: SwiftUI, Combine
- **Watch**: SwiftUI, WatchKit

### Backend
- **Firebase** - Authentication & Firestore database
- **Cloud Functions** - Points calculation, streaks, achievements
- **Firestore Rules** - Security & access control

### Motion Detection
- **CoreMotion** - Accelerometer + Gyroscope
- **Algorithm**: Peak detection with moving average smoothing
- **Web**: Optional browser motion API fallback

## 📊 Exercises Supported

1. **Push-ups**
   - Vertical acceleration pattern (Z-axis)
   - 10 base points per rep
   - Form: Symmetry of up/down motion

2. **Squats**
   - Vertical position with stability check
   - 15 base points per rep
   - Form: Gyroscope stability during hold

3. **Sit-ups**
   - Forward/backward torso motion (X-axis)
   - 10 base points per rep
   - Form: Acceleration consistency

## 🏗️ Project Structure

```
kfit/
├── web/                    # React Web App
│   ├── src/
│   │   ├── components/     # React components
│   │   ├── services/       # Firebase SDK wrapper
│   │   ├── store/          # Zustand state management
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── package.json
│   ├── vite.config.ts
│   └── README.md
│
├── ios/                    # iOS & Watch Apps
│   ├── kfit/               # iPhone App
│   │   ├── kfitApp.swift
│   │   ├── Managers/
│   │   │   ├── AuthenticationManager.swift
│   │   │   └── MotionDetectionManager.swift
│   │   └── Views/
│   │       ├── LoginView.swift
│   │       ├── DashboardView.swift
│   │       └── ExerciseTrackerView.swift
│   │
│   ├── kfitWatch/          # Apple Watch App
│   │   ├── kfitWatchApp.swift
│   │   ├── Managers/
│   │   │   ├── WatchMotionDetectionManager.swift
│   │   │   └── WatchConnectivityManager.swift
│   │   └── Views/
│   │       ├── WatchDashboardView.swift
│   │       └── WatchQuickWorkoutView.swift
│   │
│   ├── Podfile
│   ├── README.md
│   ├── SETUP.md            # Detailed iOS setup
│   └── WATCH_SETUP.md      # Apple Watch setup
│
├── firebase/               # Backend
│   ├── firestore.rules     # Security rules
│   ├── firestore.indexes.json
│   ├── functions/
│   │   ├── index.js        # Cloud Functions
│   │   └── package.json
│   ├── firebase-config.ts
│   └── SETUP.md
│
├── .firebaserc             # Firebase project config
├── firebase.json           # Hosting & functions config
├── CLAUDE.md               # Project documentation
├── LOCAL_DEV.md            # Local development guide
└── README.md               # This file
```

## 🔧 Development

### Prerequisites
- Node.js 20+
- macOS 13+ for iOS/Watch development
- Xcode 14+
- CocoaPods

### Setup Development Environment

```bash
# Clone and install
git clone https://github.com/ktrips/kfit.git
cd kfit

# Web app
cd web && npm install && npm run dev

# iOS apps
cd ../ios && pod install && open kfit.xcworkspace
```

### Database Schema

**Firestore Collections:**
```
users/{userId}/
├── profile              # User metadata
├── daily-goals/         # Daily exercise targets
├── completed-exercises/ # Workout logs
├── achievements/        # Earned badges
└── statistics/          # Aggregated metrics

exercises/               # Global exercise definitions
leaderboards/{period}/   # Weekly/monthly rankings
```

### Points System

```
Base Points = reps × exercise.basePoints

Multipliers:
- Form bonus: +10% (score ≥ 90%)
- Streak bonus: +5% per day (max 50%)
- First workout: +20%
- Daily goal complete: +100 bonus

Example: 20 push-ups (5-day streak, perfect form)
= 20 × 10 × 1.1 (form) × 1.25 (streak) = 275 points
```

## 📈 Gamification

### Achievements
- 🔥 **Iron Will** - 30-day streak
- 🏆 **Century Club** - 100+ reps in one day
- 💪 **Push Master** - 500+ push-ups total
- 🦵 **Quad Destroyer** - 500+ squats total
- 🏋️ **Core Strength** - 500+ sit-ups total
- ⏰ **Early Bird** - 10 workouts before 9 AM
- ✨ **Form Master** - 50 perfect-form exercises

### Leaderboards
- Weekly rankings (points earned Mon-Sun)
- Top 100 global rankings
- Bonus points for top 10 finishers
- Resets every Sunday at 11:59 PM UTC

## 🔐 Security

### Firestore Rules
- Users can only read/write their own data
- Global read-only access to exercises
- Public leaderboards (read-only)
- Google authentication required

## 🧪 Testing

### Web App
```bash
cd web
npm run dev              # Start dev server
npm run build            # Production build
npm run lint             # Run linter
npm run type-check       # TypeScript check
```

### iOS & Watch
```bash
cd ios
xcodebuild -scheme kfit build          # iOS
xcodebuild -scheme kfitWatch build     # Watch
xcodebuild -scheme kfit test           # Run tests
```

## 📱 Motion Detection

### iPhone (50 Hz)
- More precise for stationary exercises
- Better form analysis
- ~12 hour battery with continuous use

### Apple Watch (20 Hz)
- Battery optimized (6-8 hours continuous)
- Sufficient for rep counting
- Gyroscope adds form quality measurement

### Calibration Algorithm
1. Device held still for 3 seconds
2. Baseline acceleration measured
3. Peak threshold: baseline + 1.2 m/s²
4. Rep confirmed: peak + return to baseline

## 🚀 Deployment

### Web App to Firebase Hosting
```bash
cd web
npm run build
firebase deploy --only hosting
```

### iOS/Watch to App Store
1. Archive in Xcode
2. Validate and upload
3. Submit for review

### Firebase Backend
```bash
cd firebase/functions
npm install
firebase deploy --only functions
```

## 📚 Documentation

- **[LOCAL_DEV.md](./LOCAL_DEV.md)** - Local development guide
- **[firebase/SETUP.md](./firebase/SETUP.md)** - Backend setup
- **[ios/SETUP.md](./ios/SETUP.md)** - iOS app setup
- **[ios/WATCH_SETUP.md](./ios/WATCH_SETUP.md)** - Watch app setup
- **[web/README.md](./web/README.md)** - Web app details
- **[ios/README.md](./ios/README.md)** - iOS detailed docs

## 🎯 Current Status

✅ **Complete:**
- Web app MVP (React)
- iOS app with motion detection
- Apple Watch app with optimized motion sensors
- Firebase backend (Firestore + Cloud Functions)
- Authentication (Google Sign-in)
- Dashboard & exercise tracking
- Gamification framework

⏳ **In Progress:**
- Firebase deployment
- Firebase Hosting custom domain (fit.ktrips.net)
- App Store submission

📋 **Planned:**
- Advanced ML-based form analysis
- Social challenges & friends leaderboard
- Push notifications for reminders
- Workout video tutorials
- More exercise types

## 🤝 Contributing

1. Fork repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

MIT License - see LICENSE file for details

## 👤 Author

Created by Ktrips
- GitHub: [@ktrips](https://github.com/ktrips)
- Website: [ktrips.net](https://ktrips.net/)

## 🔗 Links

- **Live Demo:** https://fit.ktrips.net/ (coming soon)
- **GitHub:** https://github.com/ktrips/kfit
- **Firebase Project:** airgo-trip
- **Documentation:** See LOCAL_DEV.md

## 💡 FAQ

**Q: Can I use it without Google account?**
A: Not yet - Google authentication is required for syncing. Offline mode coming soon.

**Q: Does it work on iPhone simulator?**
A: Motion detection works with limited accuracy. Use physical device for best results.

**Q: How often does data sync to cloud?**
A: Real-time with Firestore listeners. ~100ms latency.

**Q: Can I use on Android?**
A: iOS and Web only for now. Android app planned.

**Q: Is my data private?**
A: Yes - Firestore rules ensure you can only access your own data.

## 📞 Support

For issues or questions:
1. Check documentation files (LOCAL_DEV.md, SETUP.md, etc.)
2. Review Firebase logs in Console
3. Check Xcode Console for iOS/Watch logs
4. Open GitHub issue with details

---

**Last Updated:** April 2026
**Version:** 1.0.0
