const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ===== POINTS CALCULATION =====
// Single source of truth: triggered when any exercise is recorded (web or iOS)
// Handles base points + form bonus + streak bonus + first-exercise-of-day bonus
exports.calculatePoints = functions.firestore
  .document('users/{userId}/completed-exercises/{exerciseId}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;
    const exerciseData = snap.data();

    try {
      // Get exercise definition for basePoints
      const exerciseDoc = await db.collection('exercises').doc(exerciseData.exerciseId).get();
      if (!exerciseDoc.exists) {
        console.error(`Exercise ${exerciseData.exerciseId} not found`);
        return null;
      }
      const exercise = exerciseDoc.data();

      // ── Base points ──────────────────────────────────────────────────────────
      let points = exerciseData.reps * exercise.basePoints;

      // ── Form bonus: +10% if formScore >= 90 (iOS motion sensor) ─────────────
      if (exerciseData.formScore && exerciseData.formScore >= 90) {
        points = Math.round(points * 1.1);
      }

      // ── Streak calculation ────────────────────────────────────────────────────
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();
      const profile = userDoc.data() || {};

      const now = exerciseData.timestamp?.toDate
        ? exerciseData.timestamp.toDate()
        : new Date();

      let newStreak = profile.streak || 0;
      if (profile.lastActiveDate) {
        const last = profile.lastActiveDate.toDate
          ? profile.lastActiveDate.toDate()
          : new Date(profile.lastActiveDate);
        const today    = new Date(now.getFullYear(),  now.getMonth(),  now.getDate());
        const lastDay  = new Date(last.getFullYear(), last.getMonth(), last.getDate());
        const diffDays = Math.round((today - lastDay) / 86400000);

        if (diffDays === 0) {
          // Already exercised today — keep current streak
        } else if (diffDays <= 3) {
          // 1 active day elapsed, gap of 0-2 days = within 2 cheat days/week allowance
          newStreak = (profile.streak || 0) + 1;
        } else {
          newStreak = 1; // Streak broken (missed more than 2 days in a row)
        }
      } else {
        newStreak = 1; // First ever exercise
      }

      // ── Streak bonus: +5% per consecutive day (max +50%) ─────────────────────
      const streakMultiplier = Math.min(1 + newStreak * 0.05, 1.5);
      points = Math.round(points * streakMultiplier);

      // ── First-exercise-of-day bonus: +20% ─────────────────────────────────────
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
      const todayEnd   = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

      const todaySnapshot = await db
        .collection('users').doc(userId)
        .collection('completed-exercises')
        .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(todayStart))
        .where('timestamp', '<=', admin.firestore.Timestamp.fromDate(todayEnd))
        .get();

      if (todaySnapshot.size === 1) {
        // This document is the only one today → first exercise of day
        points = Math.round(points * 1.2);
      }

      // ── Write to Firestore (increment to avoid race conditions) ───────────────
      await userRef.update({
        totalPoints: admin.firestore.FieldValue.increment(points),
        streak: newStreak,
        lastActiveDate: admin.firestore.Timestamp.fromDate(now),
      });

      // Store actual earned points back on the exercise record for history display
      await snap.ref.update({ pointsEarned: points });

      console.log(`[calculatePoints] user=${userId} base=${exerciseData.reps * exercise.basePoints} earned=${points} streak=${newStreak}`);
      return null;
    } catch (error) {
      console.error('Error calculating points:', error);
      throw error;
    }
  });

// ===== STREAK RESET (daily safety net) =====
// Only resets streaks for users who missed yesterday — increment is handled above
exports.updateStreaks = functions.pubsub.schedule('every day 23:59').onRun(async () => {
  try {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);

    const usersSnapshot = await db.collection('users').get();

    for (const userDoc of usersSnapshot.docs) {
      const profile = userDoc.data();
      if (!profile.lastActiveDate) continue;

      const last = profile.lastActiveDate.toDate
        ? profile.lastActiveDate.toDate()
        : new Date(profile.lastActiveDate);
      const lastDay = new Date(last.getFullYear(), last.getMonth(), last.getDate());
      const diffDays = Math.round((todayStart - lastDay) / 86400000);

      // Reset only if gap exceeds 3 days (more than 2 cheat days)
      if (diffDays >= 4 && (profile.streak || 0) > 0) {
        await userDoc.ref.update({ streak: 0 });
        console.log(`[updateStreaks] reset streak for user ${userDoc.id}`);
      }
    }
    return null;
  } catch (error) {
    console.error('Error updating streaks:', error);
    throw error;
  }
});

// ===== ACHIEVEMENT CHECKING =====
exports.checkAchievements = functions.firestore
  .document('users/{userId}/completed-exercises/{exerciseDoc}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;

    try {
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();
      const userProfile = userDoc.data();

      const allExercises = await userRef.collection('completed-exercises').get();
      const achievementsRef = userRef.collection('achievements');

      const earnedAchievements = await achievementsRef.get();
      const earnedIds = new Set(earnedAchievements.docs.map((d) => d.id));

      const achievementsList = [
        {
          id: 'early_bird',
          name: 'Early Bird',
          description: '9時前に10回トレーニング達成',
          check: async () => {
            const docs = await userRef.collection('completed-exercises').get();
            let count = 0;
            docs.forEach((doc) => {
              const t = doc.data().timestamp?.toDate?.();
              if (t && t.getHours() < 9) count++;
            });
            return count >= 10;
          },
        },
        {
          id: 'form_master',
          name: 'Form Master',
          description: 'フォームスコア90以上を50回達成',
          check: async () => {
            let n = 0;
            allExercises.forEach((doc) => {
              if (doc.data().formScore >= 90) n++;
            });
            return n >= 50;
          },
        },
        {
          id: 'iron_will',
          name: 'Iron Will',
          description: '30日連続達成',
          check: async () => (userProfile.streak || 0) >= 30,
        },
        {
          id: 'century_club',
          name: 'Century Club',
          description: '1日100rep以上',
          check: async () => {
            const now = snap.data().timestamp?.toDate?.() || new Date();
            const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
            const end   = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
            const docs = await userRef.collection('completed-exercises')
              .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(start))
              .where('timestamp', '<=', admin.firestore.Timestamp.fromDate(end))
              .get();
            let total = 0;
            docs.forEach((d) => { total += d.data().reps || 0; });
            return total >= 100;
          },
        },
        {
          id: 'pushup_master',
          name: 'Push Master',
          description: 'プッシュアップ累計500rep',
          check: async () => {
            let n = 0;
            allExercises.forEach((d) => {
              if (d.data().exerciseId === 'pushup') n += d.data().reps || 0;
            });
            return n >= 500;
          },
        },
        {
          id: 'squat_destroyer',
          name: 'Quad Destroyer',
          description: 'スクワット累計500rep',
          check: async () => {
            let n = 0;
            allExercises.forEach((d) => {
              if (d.data().exerciseId === 'squat') n += d.data().reps || 0;
            });
            return n >= 500;
          },
        },
        {
          id: 'situp_master',
          name: 'Core Strength',
          description: 'シットアップ累計500rep',
          check: async () => {
            let n = 0;
            allExercises.forEach((d) => {
              if (d.data().exerciseId === 'situp') n += d.data().reps || 0;
            });
            return n >= 500;
          },
        },
      ];

      for (const achievement of achievementsList) {
        if (!earnedIds.has(achievement.id)) {
          const isEarned = await achievement.check();
          if (isEarned) {
            await achievementsRef.doc(achievement.id).set({
              name: achievement.name,
              description: achievement.description,
              earnedDate: admin.firestore.Timestamp.now(),
              tier: 'gold',
            });
            console.log(`[checkAchievements] unlocked ${achievement.id} for user ${userId}`);
          }
        }
      }

      return null;
    } catch (error) {
      console.error('Error checking achievements:', error);
      throw error;
    }
  });

// ===== LEADERBOARD AGGREGATION =====
exports.generateWeeklyLeaderboard = functions.pubsub
  .schedule('every sunday 23:59')
  .timeZone('UTC')
  .onRun(async () => {
    try {
      const now = new Date();
      const weekNumber = getWeekNumber(now);
      const period = `week-${now.getFullYear()}-${String(weekNumber).padStart(2, '0')}`;

      const usersSnapshot = await db.collection('users').get();
      const entries = [];

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const profile = userDoc.data();
        const weekStart = getWeekStart(now);
        const weekEnd   = new Date(weekStart.getTime() + 7 * 86400000);

        const weekDocs = await db
          .collection('users').doc(userId)
          .collection('completed-exercises')
          .where('timestamp', '>=', weekStart)
          .where('timestamp', '<', weekEnd)
          .get();

        let weeklyPoints = 0;
        weekDocs.forEach((d) => { weeklyPoints += d.data().pointsEarned || d.data().points || 0; });

        if (weeklyPoints > 0) {
          entries.push({ userId, username: profile.username, points: weeklyPoints });
        }
      }

      entries.sort((a, b) => b.points - a.points);

      const leaderboardRef = db.collection('leaderboards').doc(period);
      const batch = db.batch();

      for (let i = 0; i < entries.length; i++) {
        const rank = i + 1;
        let bonus = 0;
        if (rank === 1) bonus = 500;
        else if (rank === 2) bonus = 300;
        else if (rank === 3) bonus = 200;
        else if (rank <= 10) bonus = 50;

        batch.set(leaderboardRef.collection('entries').doc(entries[i].userId), {
          ...entries[i],
          rank,
          bonusPoints: bonus,
          timestamp: admin.firestore.Timestamp.now(),
        });

        if (bonus > 0) {
          batch.update(db.collection('users').doc(entries[i].userId), {
            totalPoints: admin.firestore.FieldValue.increment(bonus),
          });
        }
      }

      await batch.commit();
      console.log(`[leaderboard] generated ${period}`);
      return null;
    } catch (error) {
      console.error('Error generating leaderboard:', error);
      throw error;
    }
  });

// ===== UTILITY =====
function getWeekNumber(date) {
  const start = new Date(date.getFullYear(), 0, 1);
  return Math.ceil(((date - start) / 86400000 + start.getDay() + 1) / 7);
}

function getWeekStart(date) {
  const d = new Date(date);
  const day = d.getDay();
  d.setDate(d.getDate() - day + (day === 0 ? -6 : 1));
  d.setHours(0, 0, 0, 0);
  return d;
}
