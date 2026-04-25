# kfit iOS App

A SwiftUI-based iOS fitness app with motion sensor exercise detection and Firebase backend integration.

## Features

- **Google Authentication** - Sign in with Google
- **Core Motion Integration** - Motion sensor rep counting for push-ups, squats, sit-ups
- **Exercise Tracking** - Log workouts with automatic or manual rep counting
- **Form Scoring** - Real-time form quality feedback based on motion patterns
- **Daily Dashboard** - View streaks, points, and workout history
- **Real-time Sync** - Firebase Firestore for data persistence

## Tech Stack

- **SwiftUI** - Modern UI framework
- **Combine** - Reactive programming
- **CoreMotion** - Motion sensor integration
- **Firebase** - Authentication & Firestore database
- **GoogleSignIn** - OAuth authentication

## Requirements

- iOS 15.0+
- Xcode 14.0+
- CocoaPods (for Firebase dependencies)

## Setup

### 1. Install Dependencies

```bash
cd ios
pod install
open kfit.xcworkspace
```

### 2. Configure Firebase

1. Download `GoogleService-Info.plist` from Firebase Console (airgo-trip project)
2. Add to Xcode project:
   - Select `kfit.xcodeproj` → `kfit` target
   - Go to `Build Phases` → `Copy Bundle Resources`
   - Add `GoogleService-Info.plist`

### 3. Configure Google Sign-In

1. Go to Firebase Console → Authentication → Google provider
2. Copy the URL Scheme (usually `com.googleusercontent.apps.YOUR_CLIENT_ID`)
3. In Xcode: Project → Targets → kfit → Info
4. Add the URL Scheme under `URL Types`

### 4. Build and Run

```bash
xcodebuild -scheme kfit -configuration Debug build
```

Or open in Xcode and press Cmd+R

## Project Structure

```
ios/kfit/
├── kfitApp.swift              # App entry point
├── Managers/
│   ├── AuthenticationManager.swift
│   └── MotionDetectionManager.swift
├── Views/
│   ├── LoginView.swift
│   ├── DashboardView.swift
│   └── ExerciseTrackerView.swift
└── Info.plist                 # App configuration
```

## Core Motion Implementation

### Motion Detection Algorithm

The app detects exercise reps by analyzing accelerometer data:

1. **Calibration** - Establishes baseline acceleration when device is stationary
2. **Peak Detection** - Monitors acceleration spikes above threshold
3. **Rep Counting** - Counts complete cycles (down + up motion)
4. **Form Scoring** - Measures motion consistency (standard deviation)

### Supported Exercises

- **Push-ups** - Vertical acceleration pattern
- **Squats** - Vertical position with gyroscope stability check
- **Sit-ups** - Forward/backward torso motion with rotation tracking

## Firebase Integration

### Firestore Collections

- `users/{userId}/completed-exercises` - Workout logs
- `users/{userId}/daily-goals` - Daily targets
- `exercises` - Global exercise definitions

### Real-time Sync

- Uses `Firestore.firestore().addSnapshotListener()` for real-time updates
- Offline support via Firestore offline persistence
- Automatic conflict resolution (last-write-wins)

## Performance Optimization

- **Accelerometer sampling** - 50 Hz for accurate rep detection
- **Motion filtering** - Baseline subtraction to reduce noise
- **Batch writes** - Groups multiple exercises into single Firestore write
- **Image caching** - Local storage of exercise form images

## Testing

### Unit Tests

```bash
xcodebuild -scheme kfit test
```

### Manual Testing Checklist

- [ ] Google Sign-in works
- [ ] Exercise selection displays all 3 exercises
- [ ] Manual rep counter increments/decrements
- [ ] Motion detection starts/stops properly
- [ ] Form score updates in real-time
- [ ] Workout saves to Firestore
- [ ] Dashboard refreshes after logging workout
- [ ] Sign out clears user data

## Troubleshooting

### Motion Detection Not Working

1. Check that app has motion sensor permissions
2. Verify `CMMotionManager` is available on device
3. Ensure app is running on physical device (simulator has limited motion support)
4. Check that `startDetection()` is called

### Firebase Auth Fails

1. Verify `GoogleService-Info.plist` is included in Xcode project
2. Check URL Scheme is correctly configured
3. Ensure Google OAuth is enabled in Firebase Console
4. Verify test device is added to Firebase auth whitelist

### Form Score Not Updating

1. Check `MotionDetectionManager.formScore` is being updated
2. Verify accelerometer data is being received
3. Ensure motion threshold is appropriate for exercise type

## Future Enhancements

- [ ] Apple Watch companion app
- [ ] Advanced form analysis with machine learning
- [ ] Push notifications for workout reminders
- [ ] Social leaderboards and friend challenges
- [ ] Workout video tutorials
- [ ] More exercise types (burpees, planks, lunges)

## Dependencies

Add to Podfile:

```ruby
pod 'Firebase/Core'
pod 'Firebase/Auth'
pod 'Firebase/Firestore'
pod 'GoogleSignIn'
```

## License

MIT
