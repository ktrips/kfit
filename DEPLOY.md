# kfit Deployment Guide

## Prerequisites

- Firebase project created (`kfit-prod`)
- Firebase CLI installed globally
- GitHub repo at https://github.com/ktrips/kfit

## Web App Deployment (fit.ktrips.net)

### 1. Build Web App

```bash
cd /home/user/fitness-app/web

# Install dependencies
npm install

# Build for production
npm run build
```

### 2. Deploy to Firebase Hosting

```bash
cd /home/user/fitness-app

# Ensure you're logged in to Firebase
firebase login

# Set default project
firebase use kfit-prod

# Deploy only hosting (faster)
firebase deploy --only hosting

# Or deploy everything
firebase deploy
```

The web app will be available at:
- Production: https://kfit-prod.web.app
- Custom domain: https://fit.ktrips.net (after domain setup)

### 3. Configure Custom Domain

1. Go to Firebase Console → Hosting
2. Click "Add custom domain"
3. Enter: `fit.ktrips.net`
4. Verify domain ownership (add TXT record to DNS)
5. Configure DNS records (A records point to Firebase IPs)

## Cloud Functions Deployment

```bash
cd /home/user/fitness-app

# Deploy only functions
firebase deploy --only functions

# Monitor function logs
firebase functions:log
```

**Functions deployed:**
- `calculatePoints` - Triggered on exercise completion
- `updateStreaks` - Daily at 11:59 PM UTC
- `checkAchievements` - Triggered on exercise completion
- `generateWeeklyLeaderboard` - Weekly on Sunday 11:59 PM UTC

## Firestore Deployment

```bash
cd /home/user/fitness-app

# Deploy security rules
firebase deploy --only firestore:rules

# Deploy indexes
firebase deploy --only firestore:indexes
```

## Environment Variables

Create `.env.local` in `web/` directory:

```
VITE_FIREBASE_API_KEY=<from Firebase Console>
VITE_FIREBASE_AUTH_DOMAIN=kfit-prod.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=kfit-prod
VITE_FIREBASE_STORAGE_BUCKET=kfit-prod.appspot.com
VITE_FIREBASE_MESSAGING_SENDER_ID=<from Firebase Console>
VITE_FIREBASE_APP_ID=<from Firebase Console>
```

Get these values from Firebase Console:
1. Go to Project Settings (gear icon)
2. Scroll to "Your apps"
3. Click the Web app icon
4. Copy the config values

## Verify Deployment

```bash
# Check deployment status
firebase hosting:sites:list

# View deployment history
firebase hosting:releases:list

# Rollback to previous version
firebase hosting:releases:rollback
```

## Local Testing Before Deploy

```bash
# Start Firebase emulator suite
cd /home/user/fitness-app
firebase emulators:start

# In another terminal, start web app dev server
cd web
npm run dev

# Visit http://localhost:5173
```

## Troubleshooting

**"Insufficient permissions"** → Check Firebase rules and authentication
**"Function timeout"** → Increase function timeout in firebase.json
**"404 on routes"** → Verify rewrites in hosting section of firebase.json
**"Cached old version"** → Clear browser cache or use incognito mode

## Monitoring

### Firebase Console
- **Hosting**: View traffic, errors, performance
- **Functions**: Monitor executions, logs, errors
- **Firestore**: View database usage, indexing status
- **Authentication**: Monitor sign-ins, user count

### Logs

```bash
# Real-time function logs
firebase functions:log --lines 50

# Deploy logs
firebase deploy --debug
```

## CI/CD Setup (GitHub Actions)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Firebase

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install dependencies
        run: npm install
      
      - name: Build web app
        run: cd web && npm run build
      
      - name: Deploy to Firebase
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          channelId: live
          projectId: kfit-prod
```

To set up:
1. Generate Firebase service account key
2. Add to GitHub Secrets as `FIREBASE_SERVICE_ACCOUNT`
3. Push to main branch to trigger deployment
