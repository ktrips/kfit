# kfit Local Development Guide

## Web App

### Start Dev Server

```bash
cd /home/user/fitness-app/web
npm run dev
```

**Access:** http://localhost:5173/

### Features Available Locally

✅ Google Sign-in with Firebase  
✅ Dashboard with stats  
✅ Exercise logging (manual counter)  
✅ Real-time Firestore sync  
✅ Dark mode (Tailwind)  
✅ Responsive design  

### Build for Production

```bash
cd /home/user/fitness-app/web
npm run build
# Output: web/dist/
```

### Environment Variables

Located in `.env.local`:
```
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=airgo-trip.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=airgo-trip
VITE_FIREBASE_STORAGE_BUCKET=...
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_APP_ID=...
```

## iOS App

### Prerequisites

- macOS 13+
- Xcode 14+
- iPhone with iOS 15+
- CocoaPods

### Setup

```bash
cd /home/user/fitness-app/ios
pod install
open kfit.xcworkspace
```

### Run on Simulator

1. Open Xcode
2. Select Product → Scheme → kfit
3. Select iOS Simulator (iPhone 15 recommended)
4. Press Cmd+R

### Run on Physical Device

1. Connect iPhone to Mac
2. In Xcode, select your device
3. Press Cmd+R
4. Trust the app on device (Settings → General → VPN & Device Management)

### Features

✅ Google Sign-in  
✅ Core Motion rep detection (50 Hz)  
✅ Manual counter fallback  
✅ Dashboard with stats  
✅ Form scoring  
✅ Haptic feedback  
✅ Firebase Firestore sync  

### Troubleshooting

**Pod install fails:**
```bash
rm -rf Pods Podfile.lock
pod install --repo-update
```

**Firebase not initializing:**
- Check GoogleService-Info.plist is in Xcode project
- Verify plist is in Bundle Resources (Build Phases)

**Motion detection not working:**
- Test on physical device (simulator has limited motion)
- Check app permissions in Settings → Privacy → Motion

## Apple Watch App

### Setup

```bash
cd /home/user/fitness-app/ios
pod install
open kfit.xcworkspace
```

### Run on Watch Simulator

1. Open Xcode
2. Select Product → Scheme → kfitWatch
3. Select Apple Watch Simulator
4. Press Cmd+R

### Run on Physical Watch

1. Ensure iPhone has kfit app installed
2. Open Apple Watch app on iPhone
3. Search for "kfit" → Install
4. Open app on Watch

### Features

✅ Motion sensor rep counting (20 Hz)  
✅ Real-time form scoring  
✅ Haptic feedback on reps  
✅ Auto-calibration  
✅ Manual counter  
✅ Quick workout logging  
✅ Watch Connectivity sync  

### Watch Calibration

1. Place watch on flat surface
2. App automatically calibrates on startup
3. Or manually: Settings → Calibrate
4. Hold steady for 3 seconds

## Firebase Emulator (Optional)

For testing without connecting to cloud:

```bash
cd /home/user/fitness-app
firebase emulators:start
```

**Emulator UI:** http://localhost:4000

Services:
- Firestore: localhost:8080
- Auth: localhost:9099
- Functions: localhost:5001
- Hosting: localhost:5000

## Testing Checklist

### Web App
- [ ] Can sign in with Google
- [ ] Dashboard loads user stats
- [ ] Can log exercise with manual counter
- [ ] Points calculated correctly
- [ ] Data syncs to Firestore
- [ ] Can sign out

### iOS App
- [ ] Sign in works
- [ ] Can select exercises
- [ ] Manual counter increments/decrements
- [ ] Motion detection detects reps
- [ ] Form score updates
- [ ] Haptic feedback on rep
- [ ] Dashboard shows logged workouts
- [ ] Data syncs across devices

### Apple Watch App
- [ ] App launches
- [ ] Can select exercises
- [ ] Manual counter works
- [ ] Motion detection counts reps
- [ ] Haptic feedback triggers
- [ ] Data syncs to iPhone
- [ ] Battery reasonable (6-8 hrs continuous)

## Common Issues

### "Firebase: Failed to connect"
- Check Firebase project is accessible
- Verify internet connection
- Check API key is valid in .env.local

### Motion detection not working on iOS
- Ensure app has permission: Settings → Privacy → Motion
- Test on physical device (iPhone 12+)
- Perform smooth, deliberate movements
- Check Console for motion manager logs

### Watch app crashes on startup
- Ensure main app is running on iPhone
- Check WatchKit Extension is built
- Clear watch app cache

### Web app won't start
- Delete node_modules: `rm -rf node_modules`
- Reinstall: `npm install`
- Clear Vite cache: `rm -rf .vite`

## Performance Tips

- Use Chrome DevTools for web app debugging
- Check Xcode Console for iOS logs
- Use Xcode Instruments for profiling
- Monitor Firebase Firestore reads/writes
- Test on real devices for accurate results

## Deploying from Local

### Web App to Firebase

```bash
cd /home/user/fitness-app
firebase deploy --only hosting
```

### iOS App to TestFlight

1. Archive in Xcode: Product → Archive
2. Distribute App
3. Select TestFlight
4. Upload

### Watch App

- Included in main iOS build
- Deploys together to TestFlight/App Store

## Development Workflow

1. **Local testing**
   ```bash
   npm run dev  # Web
   # + Xcode for iOS/Watch
   ```

2. **Build for testing**
   ```bash
   npm run build      # Web
   xcodebuild         # iOS
   ```

3. **Deploy to staging**
   ```bash
   firebase deploy --only hosting  # Web
   # TestFlight for iOS
   ```

4. **Production deployment**
   ```bash
   # See DEPLOYMENT.md
   ```

## Getting Help

- Check SETUP.md for iOS setup
- Check WATCH_SETUP.md for Watch details
- Check web/README.md for web app docs
- Review firebase/SETUP.md for backend
- Monitor Console for error messages
