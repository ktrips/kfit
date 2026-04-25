# iOS Setup Guide

## Prerequisites

- macOS 13+
- Xcode 14+
- CocoaPods
- iOS device with iOS 15+ (simulator has limited motion support)

## Step 1: Install CocoaPods Dependencies

```bash
cd /home/user/fitness-app/ios
pod install
open kfit.xcworkspace
```

## Step 2: Configure Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/) → airgo-trip project
2. Click **Project Settings** (gear icon)
3. Go to **Your apps** section
4. Click **Add app** → iOS
5. Enter Bundle ID: `com.ktrips.kfit`
6. Download `GoogleService-Info.plist`

## Step 3: Add GoogleService-Info.plist to Xcode

1. Drag `GoogleService-Info.plist` into Xcode project
2. Select the `kfit` target
3. Ensure it's in **Copy Bundle Resources** build phase

## Step 4: Configure Google Sign-In

1. In Firebase Console → Authentication → Google provider
2. Copy the iOS URL Scheme (format: `com.googleusercontent.apps.XXXXX`)
3. In Xcode:
   - Select `kfit.xcodeproj`
   - Target: `kfit` → Info tab
   - Click **+** under URL Types
   - Paste the URL Scheme

## Step 5: Request Motion Permissions

The app will automatically request motion sensor permissions on first use. Add to `Info.plist`:

```xml
<key>NSMotionUsageDescription</key>
<string>kfit uses motion sensors to accurately count your exercise reps.</string>
```

## Step 6: Build and Run

```bash
# Build
xcodebuild -scheme kfit -configuration Debug build

# Or open in Xcode and press Cmd+R
```

## Troubleshooting

### CocoaPods Issues

```bash
# Clear pods
rm -rf Pods Podfile.lock
pod install
```

### Firebase Not Initializing

- Check `GoogleService-Info.plist` is in Xcode project
- Verify plist is in Bundle Resources
- Check Console for Firebase initialization logs

### Motion Detection Not Working

- Test on physical device (simulator has limited motion)
- Check app has motion sensor permissions
- Verify `startDetection()` is called before moving

### Google Sign-In Fails

- Verify URL Scheme is correctly configured
- Check Google OAuth is enabled in Firebase Console
- Ensure app identifier matches Firebase config

## Apple Watch Setup

The Watch app automatically syncs with iOS app via Watch Connectivity:

1. Install iOS app on iPhone
2. Open Watch app on paired Apple Watch
3. Quick workout buttons sync data to iPhone

## Testing on Device

1. Connect iPhone to Mac
2. Open `kfit.xcworkspace`
3. Select physical iPhone as build target
4. Build and run (Cmd+R)

## Performance Tips

- Use physical device for testing (simulator is slow)
- Clear Firestore data periodically to speed up queries
- Disable motion detection while debugging
- Monitor Xcode Console for Firebase logs

## Next Steps

1. Configure custom domain `fit.ktrips.net` in Firebase Hosting
2. Deploy Web app
3. Test on multiple devices
4. Submit to App Store
