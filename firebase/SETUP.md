# Firebase Setup Guide

This guide walks through setting up Firebase for **kfit** - Fitness Habit App.

## Prerequisites

- Google Cloud account with billing enabled
- Firebase CLI: `npm install -g firebase-tools`
- Node.js 20+
- `gcloud` CLI (optional, for advanced operations)

## Step 1: Create Firebase Projects

### Production Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project"
3. Name: `kfit-prod`
4. Enable Google Analytics (optional)
5. Create project

### Development Project (Optional)
Repeat for `kfit-dev` to have separate development/production environments.

## Step 2: Initialize Firebase in Local Repository

```bash
cd /home/user/kfit

# Login to Firebase
firebase login

# Initialize Firebase (should auto-detect .firebaserc)
firebase init

# Or manually set the project
firebase use --add
# Select default: kfit-prod
# Select development: kfit-dev
```

## Step 3: Deploy Firestore Rules

```bash
firebase deploy --only firestore:rules
```

This deploys the security rules from `firebase/firestore.rules`.

## Step 4: Seed Initial Exercise Data

### Option A: Firebase Console (Manual)
1. Go to [Firebase Console](https://console.firebase.google.com/) → Firestore Database
2. Create collection: `exercises`
3. For each exercise in `seed-exercises.json`, create document manually

### Option B: Firebase Admin SDK (Programmatic)

Create `firebase/seed-data.js`:
```javascript
const admin = require('firebase-admin');
const serviceAccount = require('./service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const exercises = require('./seed-exercises.json').exercises;

async function seedExercises() {
  const batch = db.batch();
  
  for (const exercise of exercises) {
    const ref = db.collection('exercises').doc(exercise.id);
    batch.set(ref, exercise);
  }
  
  await batch.commit();
  console.log('Exercises seeded successfully');
  process.exit(0);
}

seedExercises().catch(err => {
  console.error('Error seeding:', err);
  process.exit(1);
});
```

Then run:
```bash
# Download service account key from Firebase Console
# Settings → Service Accounts → Generate New Private Key

node firebase/seed-data.js
```

## Step 5: Deploy Firestore Indexes

```bash
firebase deploy --only firestore:indexes
```

This creates composite indexes needed for complex queries.

## Step 6: Deploy Cloud Functions

```bash
# Install dependencies
cd firebase/functions
npm install

# Deploy functions
cd ../..
firebase deploy --only functions
```

This deploys:
- `calculatePoints`: Triggered on exercise completion
- `updateStreaks`: Daily streak update (11:59 PM UTC)
- `checkAchievements`: Achievement unlocking logic
- `generateWeeklyLeaderboard`: Weekly aggregation (Sunday 11:59 PM UTC)

## Step 7: Set Up Google Sign-In

1. Go to Firebase Console → Authentication
2. Click "Get Started"
3. Enable "Google" provider
4. Configure OAuth consent screen:
   - User Type: External
   - Add required scopes: email, profile
   - Add test users (for development)

## Step 8: Configure Environment Variables

Create `.env.example` in project root:
```
VITE_FIREBASE_API_KEY=
VITE_FIREBASE_AUTH_DOMAIN=
VITE_FIREBASE_PROJECT_ID=
VITE_FIREBASE_STORAGE_BUCKET=
VITE_FIREBASE_MESSAGING_SENDER_ID=
VITE_FIREBASE_APP_ID=
```

Get these values from Firebase Console → Project Settings → Your apps → Web app.

## Step 9: Verify Deployment

```bash
# Check function logs
firebase functions:log

# Check Firestore is accessible
firebase shell
> db.collection('exercises').get().then(snap => console.log(snap.size))
```

## Testing with Emulator

For local development, use Firebase emulator:

```bash
# Start emulator suite
firebase emulators:start

# Emulator UI will be available at http://localhost:4000
```

The emulator runs:
- Firestore (port 8080)
- Cloud Functions (port 5001)
- Auth (port 9099)
- Hosting (port 5000)

## Switching Between Projects

```bash
# List projects
firebase projects:list

# Switch to development
firebase use development

# Switch to production
firebase use default
```

## Common Operations

### View Firestore Data
```bash
firebase firestore:list
firebase firestore:get users/{userId}
```

### Clear Firestore (Caution!)
```bash
firebase firestore:delete users --recursive --all
```

### Monitor Functions
```bash
firebase functions:log --lines 50
```

### Local Testing of Functions

Edit `firebase/functions/index.js` and test locally:
```bash
firebase emulators:start --only functions

# In another terminal:
npm run test
```

## Troubleshooting

### "Missing or insufficient permissions"
- Verify Firestore rules in `firebase/firestore.rules`
- Ensure user is authenticated
- Check user UID matches rules

### Functions not triggering
- Check function logs: `firebase functions:log`
- Verify trigger path in function matches collection structure
- Ensure function was deployed: `firebase deploy --only functions`

### Emulator issues
- Clear emulator data: `rm -rf ~/.config/firebase/`
- Restart emulator: `firebase emulators:start --import=./emulator-data`

## Production Considerations

1. **Enable Backups**: Firebase Console → Firestore → Manage backups
2. **Set Up Monitoring**: Firebase Console → Performance monitoring
3. **Enable Crash Reporting**: Firebase Console → Crash Reporting
4. **Implement Rate Limiting**: Add to Cloud Functions for security
5. **Regular Security Audits**: Review Firestore rules quarterly

## Next Steps

1. Deploy web app to Firebase Hosting: `firebase deploy --only hosting`
2. Set up iOS app authentication via GoogleSignIn pod
3. Configure push notifications for daily reminders

For detailed Firebase documentation:
- [Firestore Docs](https://firebase.google.com/docs/firestore)
- [Cloud Functions Docs](https://firebase.google.com/docs/functions)
- [Authentication Docs](https://firebase.google.com/docs/auth)
