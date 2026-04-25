const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ===== POINTS CALCULATION =====
// Triggered when a user completes an exercise
exports.calculatePoints = functions.firestore
  .document('users/{userId}/completed-exercises/{exerciseId}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;
    const exerciseData = snap.data();

    try {
      // Get exercise definition
      const exerciseRef = db.collection('exercises').doc(exerciseData.exerciseId);
      const exerciseDoc = await exerciseRef.get();

      if (!exerciseDoc.exists) {
        console.error(`Exercise ${exerciseData.exerciseId} not found`);
        return null;
      }

      const exercise = exerciseDoc.data();

      // Calculate base points
      let points = exerciseData.reps * exercise.basePoints;

      // Apply form bonus: +10% for perfect form (formScore >= 90)
      if (exerciseData.formScore && exerciseData.formScore >= 90) {
        points = Math.round(points * 1.1);
      }

      // Get current user profile for streak bonus
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();
      const userProfile = userDoc.data();
      const currentStreak = userProfile.streak || 0;

      // Apply streak bonus: +5% per consecutive day (max 50%)
      const streakMultiplier = Math.min(1 + (currentStreak * 0.05), 1.5);
      points = Math.round(points * streakMultiplier);

      // Check if this is first exercise of the day (20% bonus)
      const today = new Date().toISOString().split('T')[0];
      const todayExercises = await db
        .collection('users')
        .doc(userId)
        .collection('completed-exercises')
        .where('timestamp', '>=', new Date(`${today}T00:00:00Z`))
        .get();

      if (todayExercises.size === 1) {
        // This is the first exercise of the day
        points = Math.round(points * 1.2);
      }

      // Add daily goal completion check
      const dailyGoalRef = db
        .collection('users')
        .doc(userId)
        .collection('daily-goals')
        .where('exerciseId', '==', exerciseData.exerciseId)
        .where('date', '==', today);

      const dailyGoalDocs = await dailyGoalRef.get();
      let goalCompletionBonus = 0;
      if (!dailyGoalDocs.empty) {
        const goalDoc = dailyGoalDocs.docs[0];
        const goal = goalDoc.data();
        if (goal.completedReps + exerciseData.reps >= goal.targetReps) {
          goalCompletionBonus = 100;
        }
      }

      // Update user profile with new total points
      const newTotalPoints = (userProfile.totalPoints || 0) + points + goalCompletionBonus;
      await userRef.update({
        totalPoints: newTotalPoints,
        lastActiveDate: admin.firestore.Timestamp.now(),
      });

      console.log(
        `Points calculated for user ${userId}: ${points} points (streak: ${currentStreak}x)`
      );

      return null;
    } catch (error) {
      console.error('Error calculating points:', error);
      throw error;
    }
  });

// ===== STREAK TRACKING =====
// Runs daily at 11:59 PM UTC to update streaks
exports.updateStreaks = functions.pubsub.schedule('every day 23:59').onRun(
  async (context) => {
    try {
      const now = new Date();
      const yesterday = new Date(now.getTime() - 86400000); // 24 hours ago
      const yesterdayDate = yesterday.toISOString().split('T')[0];

      // Get all users
      const usersSnapshot = await db.collection('users').get();

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userProfile = userDoc.data();
        const lastActiveDate = userProfile.lastActiveDate?.toDate?.();

        // Check if user exercised yesterday
        const yesterdayExercises = await db
          .collection('users')
          .doc(userId)
          .collection('completed-exercises')
          .where('timestamp', '>=', new Date(`${yesterdayDate}T00:00:00Z`))
          .where('timestamp', '<', new Date(`${yesterdayDate}T23:59:59Z`))
          .limit(1)
          .get();

        if (!yesterdayExercises.empty) {
          // User exercised yesterday, increment streak
          const newStreak = (userProfile.streak || 0) + 1;
          const streakBonus = Math.min(newStreak * 10, 100); // Bonus points for streak milestone

          await userDoc.ref.update({
            streak: newStreak,
            lastStreakDate: admin.firestore.Timestamp.fromDate(yesterday),
            totalPoints: (userProfile.totalPoints || 0) + streakBonus,
          });

          console.log(`User ${userId} streak updated to ${newStreak}`);
        } else {
          // User didn't exercise yesterday, reset streak
          await userDoc.ref.update({
            streak: 0,
          });

          console.log(`User ${userId} streak reset`);
        }
      }

      return null;
    } catch (error) {
      console.error('Error updating streaks:', error);
      throw error;
    }
  }
);

// ===== ACHIEVEMENT CHECKING =====
// Triggered when user profile is updated or exercise completed
exports.checkAchievements = functions.firestore
  .document('users/{userId}/completed-exercises/{exerciseDoc}')
  .onCreate(async (snap, context) => {
    const { userId } = context.params;

    try {
      const userRef = db.collection('users').doc(userId);
      const userDoc = await userRef.get();
      const userProfile = userDoc.data();

      // Get all completed exercises for this user
      const allExercises = await userRef.collection('completed-exercises').get();
      const achievementsRef = userRef.collection('achievements');

      // Get already earned achievements
      const earnedAchievements = await achievementsRef.get();
      const earnedAchievementIds = new Set(earnedAchievements.docs.map((d) => d.id));

      // Define achievements
      const achievementsList = [
        {
          id: 'early_bird',
          name: 'Early Bird',
          description: 'Complete 10 workouts before 9 AM',
          check: async () => {
            const earlyWorkouts = await userRef
              .collection('completed-exercises')
              .where('timestamp', '>=', new Date('2024-01-01T00:00:00Z'))
              .get();

            let count = 0;
            earlyWorkouts.forEach((doc) => {
              const time = doc.data().timestamp.toDate();
              if (time.getHours() < 9) count++;
            });
            return count >= 10;
          },
        },
        {
          id: 'form_master',
          name: 'Form Master',
          description: '50 perfect-form exercises',
          check: async () => {
            let perfectFormCount = 0;
            allExercises.forEach((doc) => {
              if (doc.data().formScore >= 90) perfectFormCount++;
            });
            return perfectFormCount >= 50;
          },
        },
        {
          id: 'iron_will',
          name: 'Iron Will',
          description: '30-day streak',
          check: async () => userProfile.streak >= 30,
        },
        {
          id: 'century_club',
          name: 'Century Club',
          description: '100+ reps in one day',
          check: async () => {
            const today = new Date().toISOString().split('T')[0];
            const todayExercises = await userRef
              .collection('completed-exercises')
              .where('timestamp', '>=', new Date(`${today}T00:00:00Z`))
              .get();

            let totalReps = 0;
            todayExercises.forEach((doc) => {
              totalReps += doc.data().reps;
            });
            return totalReps >= 100;
          },
        },
        {
          id: 'pushup_master',
          name: 'Push Master',
          description: '500 push-ups total',
          check: async () => {
            let totalPushups = 0;
            allExercises.forEach((doc) => {
              if (doc.data().exerciseId === 'pushup') {
                totalPushups += doc.data().reps;
              }
            });
            return totalPushups >= 500;
          },
        },
        {
          id: 'squat_destroyer',
          name: 'Quad Destroyer',
          description: '500 squats total',
          check: async () => {
            let totalSquats = 0;
            allExercises.forEach((doc) => {
              if (doc.data().exerciseId === 'squat') {
                totalSquats += doc.data().reps;
              }
            });
            return totalSquats >= 500;
          },
        },
        {
          id: 'situp_master',
          name: 'Core Strength',
          description: '500 sit-ups total',
          check: async () => {
            let totalSitups = 0;
            allExercises.forEach((doc) => {
              if (doc.data().exerciseId === 'situp') {
                totalSitups += doc.data().reps;
              }
            });
            return totalSitups >= 500;
          },
        },
      ];

      // Check each achievement
      for (const achievement of achievementsList) {
        if (!earnedAchievementIds.has(achievement.id)) {
          const isEarned = await achievement.check();
          if (isEarned) {
            await achievementsRef.doc(achievement.id).set({
              name: achievement.name,
              description: achievement.description,
              earnedDate: admin.firestore.Timestamp.now(),
              tier: 'gold',
            });

            console.log(`Achievement unlocked for user ${userId}: ${achievement.id}`);
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
// Runs weekly on Sunday at 11:59 PM UTC
exports.generateWeeklyLeaderboard = functions.pubsub
  .schedule('every sunday 23:59')
  .timeZone('UTC')
  .onRun(async (context) => {
    try {
      const now = new Date();
      const weekNumber = getWeekNumber(now);
      const year = now.getFullYear();
      const period = `week-${year}-${String(weekNumber).padStart(2, '0')}`;

      // Get all users
      const usersSnapshot = await db.collection('users').get();
      const leaderboardEntries = [];

      // Calculate points for each user this week
      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userProfile = userDoc.data();

        // Get exercises completed this week
        const weekStart = getWeekStart(now);
        const weekEnd = new Date(weekStart.getTime() + 7 * 86400000);

        const weekExercises = await db
          .collection('users')
          .doc(userId)
          .collection('completed-exercises')
          .where('timestamp', '>=', weekStart)
          .where('timestamp', '<', weekEnd)
          .get();

        let weeklyPoints = 0;
        weekExercises.forEach((doc) => {
          weeklyPoints += doc.data().points || 0;
        });

        if (weeklyPoints > 0) {
          leaderboardEntries.push({
            userId,
            username: userProfile.username,
            points: weeklyPoints,
            timestamp: admin.firestore.Timestamp.now(),
          });
        }
      }

      // Sort and rank
      leaderboardEntries.sort((a, b) => b.points - a.points);

      // Store leaderboard
      const leaderboardRef = db.collection('leaderboards').doc(period);
      const batch = db.batch();

      for (let i = 0; i < leaderboardEntries.length; i++) {
        const entry = leaderboardEntries[i];
        const rank = i + 1;

        // Award bonus points to top 10
        let bonusPoints = 0;
        if (rank === 1) bonusPoints = 500;
        else if (rank === 2) bonusPoints = 300;
        else if (rank === 3) bonusPoints = 200;
        else if (rank <= 10) bonusPoints = 50;

        // Add to leaderboard
        batch.set(leaderboardRef.collection('entries').doc(entry.userId), {
          ...entry,
          rank,
          bonusPoints,
        });

        // Add bonus points to user profile
        if (bonusPoints > 0) {
          batch.update(db.collection('users').doc(entry.userId), {
            totalPoints: admin.firestore.FieldValue.increment(bonusPoints),
          });
        }
      }

      await batch.commit();
      console.log(`Leaderboard generated for ${period}`);

      return null;
    } catch (error) {
      console.error('Error generating leaderboard:', error);
      throw error;
    }
  });

// ===== UTILITY FUNCTIONS =====
function getWeekNumber(date) {
  const firstDayOfYear = new Date(date.getFullYear(), 0, 1);
  const pastDaysOfYear = (date - firstDayOfYear) / 86400000;
  return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7);
}

function getWeekStart(date) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.setDate(diff));
}
