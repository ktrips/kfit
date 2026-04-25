# Apple Watch App Setup Guide

## Features

- **Motion Sensor Rep Counting** - Accelerometer + Gyroscope for accurate detection
- **Real-time Form Scoring** - Gyro data analyzes movement quality
- **Quick Workout Logging** - One-tap exercise tracking on wrist
- **Haptic Feedback** - Vibration on rep completion
- **Offline Support** - Works without iPhone nearby
- **Battery Optimized** - 20 Hz sampling rate (vs 50 Hz on iPhone)

## Watch Compatibility

- watchOS 9.0+
- Apple Watch Series 4 or later
- Requires: Accelerometer + Gyroscope

## Installation

### Step 1: Add Watch Target to Xcode

1. Open `kfit.xcworkspace`
2. File → New → Target → watchOS App
3. Name: `kfitWatch`
4. Check "Include WatchKit Extension"

### Step 2: Install Dependencies

Update `Podfile`:

```ruby
target 'kfitWatch' do
  pod 'Firebase/Core'
  pod 'Firebase/Firestore'
end

target 'kfitWatchKit Extension' do
  pod 'Firebase/Core'
  pod 'Firebase/Firestore'
end
```

Run: `pod install`

### Step 3: Add GoogleService-Info.plist

1. Download from Firebase Console
2. Add to both Watch app and Extension targets
3. In Xcode → Build Phases → Copy Bundle Resources

### Step 4: Configure Watch App Entitlements

1. Select `kfitWatch` target → Signing & Capabilities
2. Add capabilities:
   - HealthKit (for future features)
   - Background Modes → Background Processing

## Motion Sensor Calibration

The watch automatically calibrates on app launch:

1. Place watch on flat, stable surface
2. Keep still for 3 seconds
3. App establishes baseline acceleration
4. Green checkmark confirms calibration

### Manual Calibration

Users can recalibrate anytime:
1. Open Watch app → Settings tab
2. Tap "Calibrate"
3. Hold steady for 3 seconds

## Rep Detection Algorithm

### Movement Detection (Accelerometer)

```
Baseline: 1.0 m/s²
Peak Threshold: 1.2 m/s² above baseline
Buffer Size: 5 readings for smoothing

Rep Detected When:
1. Acceleration spikes above threshold
2. Returns to baseline within buffer window
3. Confirms peak was legitimate motion
```

### Form Quality (Gyroscope)

```
Rotation Rate Penalty:
- Clean form: < 2 rad/s (form score > 90%)
- Good form: 2-4 rad/s (form score 70-90%)
- Poor form: > 4 rad/s (form score < 70%)

Form Score = 100 - (rotation_magnitude * 10)
```

## Battery Optimization

The Watch version uses optimized settings:

| Setting | iPhone | Watch |
|---------|--------|-------|
| Accelerometer Rate | 50 Hz | 20 Hz |
| Gyro Rate | 50 Hz | 20 Hz |
| Buffer Size | 10 | 5 |
| Update Interval | 20ms | 50ms |

**Expected Battery Life:** 6-8 hours continuous use

## Watch Connectivity

The Watch app syncs with iPhone via `WatchConnectivityManager`:

```
Watch → iPhone:
- Completed workouts
- Daily stats updates
- Achievements unlocked

iPhone → Watch:
- User profile updates
- Firestore changes
- Leaderboard updates
```

Real-time sync triggers:
- Workout completion
- Achievement unlocked
- Points earned

## Testing

### Test on Device

```bash
# Build for watch
xcodebuild -scheme kfitWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 8'

# Or in Xcode: Select kfitWatch → physical watch → Cmd+R
```

### Test Motion Detection

1. Put watch on wrist
2. Perform actual exercise (real motion needed)
3. Watch detects and counts reps
4. Haptic feedback confirms each rep

### Test Calibration

1. Place on table (stationary)
2. Run calibration
3. Verify baseline acceleration in logs
4. Perform exercise - reps should count accurately

## Troubleshooting

### Motion Detection Not Working

**Problem:** Reps not counting despite movement
**Solutions:**
1. Recalibrate (Settings → Calibrate)
2. Check watch position - wrist-worn works best
3. Ensure motion is smooth, not jerky
4. Verify watch has accelerometer/gyro (Series 4+)

### Watch Connectivity Failing

**Problem:** Data not syncing to iPhone
**Solutions:**
1. Ensure iPhone is nearby and unlocked
2. Check both apps are running
3. Verify WatchConnectivity delegate is set
4. Restart watch and iPhone

### Battery Draining Fast

**Problem:** Watch battery dies quickly
**Solutions:**
1. Reduce update frequency (edit UpdateInterval)
2. Disable continuous detection
3. Close app when not in use
4. Update watchOS to latest version

### Form Score Always 100%

**Problem:** Form score not reflecting movement quality
**Solutions:**
1. Ensure gyroscope is working
2. Recalibrate motion sensors
3. Check gyroscope data in logs
4. Perform more exaggerated movements

## Advanced Configuration

### Adjust Detection Sensitivity

Edit `WatchMotionDetectionManager.swift`:

```swift
private let peakThreshold: Double = 1.2  // Lower = more sensitive
private let bufferSize = 5                // Larger = smoother but slower
```

### Change Haptic Feedback

```swift
WKInterfaceDevice.current().play(.notification)  // Current
WKInterfaceDevice.current().play(.success)       // Alternative
WKInterfaceDevice.current().play(.failure)       // Alternative
```

### Enable Continuous Heart Rate

For future HR-based features:

```swift
private let healthStore = HKHealthStore()

func startHeartRateMonitoring() {
    let heartRateQuery = HKQuery.predicateForSamples(
        withStart: Date(),
        end: nil,
        options: .strictStartDate
    )
    // Implementation...
}
```

## Performance Metrics

Target performance on Apple Watch:

- **Rep Detection Latency:** < 200ms
- **Form Score Update:** Real-time
- **Battery Impact:** ~2% per 5-min workout
- **Memory Usage:** < 50MB
- **Startup Time:** < 1 second

## Future Enhancements

- [ ] Heart rate integration
- [ ] Advanced ML-based form analysis
- [ ] Complication widgets
- [ ] Siri voice control
- [ ] Workout app integration
- [ ] Breathing/cool-down coaching
- [ ] Multi-exercise sessions

## Resources

- [watchOS Dev Guide](https://developer.apple.com/watchos/)
- [CoreMotion Reference](https://developer.apple.com/documentation/coremotion/)
- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/)
- [WatchKit UI Guide](https://developer.apple.com/watchkit/)

## Support

For issues:
1. Check Console for motion manager logs
2. Verify watch hardware capabilities
3. Test on physical device (simulator limited)
4. Check iOS app is running for sync
