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

// ===== RETENTION COHORT STATS =====
// 週1回、全ユーザーの retention/summary（クライアントが記録する活動日マップ）から
// 7/30/90 日継続率を集計し、public-stats/retention に公開する。
// LP・90日チャレンジページ・ストア文言の「90日継続率 X%」の唯一のデータソース。
//
// 定義:
//   継続日数 = 活動日マップ上で「3日以上空けずに」続いた期間の最長スパン
//              （iOS のストリーク3日猶予と同じ基準）
//   Dn 継続率 = 初回活動から n 日以上経過したユーザーのうち、
//               継続日数が n 日以上に達した人の割合
exports.computeRetentionStats = functions.pubsub
  .schedule('every monday 03:00')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const MS_DAY = 86400000;
    const today = new Date();
    const MILESTONES = [7, 30, 90];
    const buckets = {};
    MILESTONES.forEach((n) => { buckets[n] = { eligible: 0, reached: 0 }; });

    const userRefs = await db.collection('users').listDocuments();

    for (const userRef of userRefs) {
      try {
        const snap = await userRef.collection('retention').doc('summary').get();
        if (!snap.exists) continue;
        const data = snap.data() || {};
        const days = Object.keys(data.days || {}).sort();
        if (days.length === 0) continue;

        // 3日猶予の最長継続スパンを計算
        let runStart = new Date(days[0]);
        let prev = new Date(days[0]);
        let longestSpan = 1;
        for (let i = 1; i < days.length; i++) {
          const cur = new Date(days[i]);
          const gap = Math.round((cur - prev) / MS_DAY);
          if (gap > 3) {
            runStart = cur; // 3日超の空白でリセット
          }
          longestSpan = Math.max(longestSpan, Math.round((cur - runStart) / MS_DAY) + 1);
          prev = cur;
        }

        const firstDay = new Date(data.firstActiveDay || days[0]);
        const daysSinceFirst = Math.round((today - firstDay) / MS_DAY);

        for (const n of MILESTONES) {
          if (daysSinceFirst >= n) {
            buckets[n].eligible += 1;
            if (longestSpan >= n) buckets[n].reached += 1;
          }
        }
      } catch (e) {
        console.error(`retention read failed for ${userRef.id}:`, e);
      }
    }

    const toStat = (b) => ({
      eligible: b.eligible,
      reached: b.reached,
      rate: b.eligible > 0 ? Math.round((b.reached / b.eligible) * 1000) / 10 : null,
    });

    await db.collection('public-stats').doc('retention').set({
      d7: toStat(buckets[7]),
      d30: toStat(buckets[30]),
      d90: toStat(buckets[90]),
      computedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log('Retention stats:', JSON.stringify({
      d7: toStat(buckets[7]), d30: toStat(buckets[30]), d90: toStat(buckets[90]),
    }));
    return null;
  });

// ===== AI PROXY =====
// 「AI 機能は別途 API キー要」の廃止（docs/ai_proxy_plan.md 参照）。
// サーバー側の API キーで AI を代理呼び出しし、ユーザーには API キーの
// 概念を一切見せない。コストは月次クォータで管理する。
//
// クォータ（1ヶ月あたりの呼び出し回数）:
//   Free: 5 回（オンボーディングで「写真だけで記録」を体験させる）
//   Plus: 300 回
//
// API キーの設定:
//   firebase functions:config:set ai.openai_key="sk-..."
// Plus 判定:
//   users/{uid} ドキュメントの isPlus フィールド（iOS が購入時に書き込む）
const AI_QUOTA = { free: 5, plus: 300 };
const AI_DEFAULT_MODEL = 'gpt-4o-mini';

exports.aiProxy = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
    }
    const uid = context.auth.uid;
    const prompt = (data && data.prompt) || '';
    const imageBase64 = data && data.imageBase64; // 任意（食事写真解析用）
    if (!prompt || typeof prompt !== 'string' || prompt.length > 8000) {
      throw new functions.https.HttpsError('invalid-argument', 'prompt が不正です');
    }

    // ── Plus 判定 + 月次クォータ ─────────────────────────────
    const userSnap = await db.collection('users').doc(uid).get();
    const isPlus = !!(userSnap.data() || {}).isPlus;
    const quota = isPlus ? AI_QUOTA.plus : AI_QUOTA.free;

    const monthKey = new Date().toISOString().slice(0, 7); // "2026-07"
    const usageRef = db.collection('users').doc(uid)
      .collection('ai-usage').doc(monthKey);
    const usageSnap = await usageRef.get();
    const used = (usageSnap.data() || {}).count || 0;
    if (used >= quota) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        isPlus ? '今月のAI利用上限に達しました' : 'AI解析の無料枠を使い切りました。Plusで月300回まで使えます'
      );
    }

    // ── OpenAI 呼び出し（サーバー側キー） ────────────────────
    const apiKey = (functions.config().ai || {}).openai_key;
    if (!apiKey) {
      throw new functions.https.HttpsError('failed-precondition', 'AI プロキシが未設定です');
    }

    const content = imageBase64
      ? [
          { type: 'text', text: prompt },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
        ]
      : prompt;

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: (data && data.model) || AI_DEFAULT_MODEL,
        max_tokens: 1000,
        messages: [{ role: 'user', content }],
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      console.error('aiProxy upstream error:', res.status, body.slice(0, 500));
      throw new functions.https.HttpsError('internal', 'AI 解析に失敗しました');
    }
    const json = await res.json();
    const text = (((json.choices || [])[0] || {}).message || {}).content || '';

    // 使用量を記録（失敗時はカウントしない）
    await usageRef.set(
      { count: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    return { text, used: used + 1, quota, isPlus };
  });
