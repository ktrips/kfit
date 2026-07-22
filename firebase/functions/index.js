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
      const achievementsRef = userRef.collection('achievements');
      const ACHIEVEMENT_COUNT = 7;

      const earnedAchievements = await achievementsRef.get();
      const earnedIds = new Set(earnedAchievements.docs.map((d) => d.id));

      // 全実績を獲得済みなら、completed-exercises 全件読み取りすら不要
      // （書き込みのたびに毎回フルスキャンしていたコストを回避）
      if (earnedIds.size >= ACHIEVEMENT_COUNT) return null;

      const userDoc = await userRef.get();
      const userProfile = userDoc.data();

      // completed-exercises の全件取得は、実際に必要な実績チェックが
      // 発生するまで遅延させ、1回の呼び出しにつき最大1回のみ実行する
      // （以前は early_bird 用にもう一度同じ全件取得をしていた）
      let allExercisesPromise = null;
      const getAllExercises = () => {
        if (!allExercisesPromise) {
          allExercisesPromise = userRef.collection('completed-exercises').get();
        }
        return allExercisesPromise;
      };

      const achievementsList = [
        {
          id: 'early_bird',
          name: 'Early Bird',
          description: '9時前に10回トレーニング達成',
          check: async () => {
            const docs = await getAllExercises();
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
            const docs = await getAllExercises();
            let n = 0;
            docs.forEach((doc) => {
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
            const docs = await getAllExercises();
            let n = 0;
            docs.forEach((d) => {
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
            const docs = await getAllExercises();
            let n = 0;
            docs.forEach((d) => {
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
            const docs = await getAllExercises();
            let n = 0;
            docs.forEach((d) => {
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
      const weekStart = getWeekStart(now);
      const weekEnd   = new Date(weekStart.getTime() + 7 * 86400000);

      // ユーザーごとのクエリを直列awaitしていたため、ユーザー数が多いほど
      // 実行時間が線形に伸びていた（N+1）。独立したクエリなので並列実行する。
      const entries = (await Promise.all(usersSnapshot.docs.map(async (userDoc) => {
        const userId = userDoc.id;
        const profile = userDoc.data();

        const weekDocs = await db
          .collection('users').doc(userId)
          .collection('completed-exercises')
          .where('timestamp', '>=', weekStart)
          .where('timestamp', '<', weekEnd)
          .get();

        let weeklyPoints = 0;
        weekDocs.forEach((d) => { weeklyPoints += d.data().pointsEarned || d.data().points || 0; });

        return weeklyPoints > 0 ? { userId, username: profile.username, points: weeklyPoints } : null;
      }))).filter((e) => e !== null);

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

// ===== ACHIEVEMENT HISTORY RETENTION =====
// 週次・月次到達度カレンダー（summaries/daily-{yyyy-MM-dd}.achievementPercent）は
// 直近6ヶ月分のみ日次データを保持する。それより前の月は平均値だけを
// summaries/monthly-avg-{yyyy-MM} に集約し、日次ドキュメントからは
// achievementPercent フィールドを削除する（他の日次集計フィールドは残す）。
// 保持月数は iOS 側 DashboardView.achievementHistoryRetentionMonths と揃えること。
const ACHIEVEMENT_HISTORY_RETENTION_MONTHS = 6;

exports.pruneAchievementHistory = functions.pubsub
  .schedule('0 4 1 * *') // 毎月1日 04:00 JST
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const now = new Date();
    const targetMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    targetMonthStart.setMonth(targetMonthStart.getMonth() - ACHIEVEMENT_HISTORY_RETENTION_MONTHS);
    const monthKey = `${targetMonthStart.getFullYear()}-${String(targetMonthStart.getMonth() + 1).padStart(2, '0')}`;

    const startId = `daily-${monthKey}-01`;
    const endId = `daily-${monthKey}-31`;

    const userRefs = await db.collection('users').listDocuments();
    let processedUsers = 0;

    await Promise.all(userRefs.map(async (userRef) => {
      const summariesRef = userRef.collection('summaries');
      const snap = await summariesRef
        .where(admin.firestore.FieldPath.documentId(), '>=', startId)
        .where(admin.firestore.FieldPath.documentId(), '<=', endId)
        .get();

      const withPercent = snap.docs.filter((d) => typeof d.data().achievementPercent === 'number');
      if (withPercent.length === 0) return;

      const total = withPercent.reduce((sum, d) => sum + d.data().achievementPercent, 0);
      const average = Math.round(total / withPercent.length);

      const batch = db.batch();
      batch.set(summariesRef.doc(`monthly-avg-${monthKey}`), {
        averageAchievementPercent: average,
        daysRecorded: withPercent.length,
        computedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      withPercent.forEach((d) => {
        batch.update(d.ref, {
          achievementPercent: admin.firestore.FieldValue.delete(),
          achievementPercentUpdatedAt: admin.firestore.FieldValue.delete(),
        });
      });
      await batch.commit();
      processedUsers += 1;
    }));

    console.log(`[pruneAchievementHistory] month=${monthKey} processedUsers=${processedUsers}`);
    return null;
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

    // ユーザーごとの retention/summary 読み取りを直列awaitしていたため、
    // ユーザー数が多いほど実行時間が線形に伸びていた（N+1）。
    // 各ユーザーの読み取り・スパン計算は独立しているので並列実行し、
    // buckets への集計だけ後段でまとめて行う。
    const perUserResults = await Promise.all(userRefs.map(async (userRef) => {
      try {
        const snap = await userRef.collection('retention').doc('summary').get();
        if (!snap.exists) return null;
        const data = snap.data() || {};
        const days = Object.keys(data.days || {}).sort();
        if (days.length === 0) return null;

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
        return { daysSinceFirst, longestSpan };
      } catch (e) {
        console.error(`retention read failed for ${userRef.id}:`, e);
        return null;
      }
    }));

    for (const result of perUserResults) {
      if (!result) continue;
      for (const n of MILESTONES) {
        if (result.daysSinceFirst >= n) {
          buckets[n].eligible += 1;
          if (result.longestSpan >= n) buckets[n].reached += 1;
        }
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

// ===== WEEKLY REPORT AI COMMENT =====
// 週次レポートカード用の AI コーチングコメントを生成する callable 関数。
// WeeklyReportView（iOS）から呼ばれ、結果は shared-reports ドキュメントにも保存される。
// 認証必須・Plus クォータ（AI_QUOTA）を消費しない（週1回の軽量呼び出しのため無料扱い）。
exports.generateWeeklyReport = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB', secrets: ['OPENAI_API_KEY'] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
    }

    const { streak = 0, weekSets = 0, weekXP = 0, avgHRV, sleepScore } = data || {};

    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      // API キー未設定時はルールベースのコメントを返す（フォールバック）
      return { comment: generateRuleBasedComment(streak, weekSets, weekXP), aiGenerated: false };
    }

    // プロンプト構築（日本語・短めのコーチングコメント）
    let context_str = `ストリーク: ${streak}日連続、今週のセット: ${weekSets}回、XP: ${weekXP}`;
    if (avgHRV != null) context_str += `、平均HRV: ${Math.round(avgHRV)}ms`;
    if (sleepScore != null) context_str += `、睡眠スコア: ${sleepScore}/100`;

    const prompt = [
      'あなたは「Fitingo」というフィットネス習慣化アプリのコーチです。',
      `ユーザーの今週の実績: ${context_str}`,
      '',
      '以下の条件で日本語のコーチングコメントを1文（60文字以内）で生成してください:',
      '- 継続を褒め、次のアクションを1つだけ提案する',
      '- 数値に触れて具体的にする',
      '- 「今度こそ、続く。」というFitingoのメッセージと一致させる',
      '- 励ましを含め、前向きなトーンにする',
      '- マークダウン・記号は使わない。純粋なテキストのみ',
      '',
      'コメント（60文字以内）:',
    ].join('\n');

    try {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          max_completion_tokens: 150,
          temperature: 0.7,
          messages: [{ role: 'user', content: prompt }],
        }),
      });

      if (!res.ok) {
        const err = await res.text();
        console.error('generateWeeklyReport upstream error:', res.status, err.slice(0, 200));
        return { comment: generateRuleBasedComment(streak, weekSets, weekXP), aiGenerated: false };
      }

      const json = await res.json();
      const comment = ((json.choices?.[0]?.message?.content) || '').trim().slice(0, 80);
      return { comment: comment || generateRuleBasedComment(streak, weekSets, weekXP), aiGenerated: true };
    } catch (e) {
      console.error('generateWeeklyReport error:', e);
      return { comment: generateRuleBasedComment(streak, weekSets, weekXP), aiGenerated: false };
    }
  });

/** API キー未設定時のルールベースコメント生成（フォールバック） */
function generateRuleBasedComment(streak, weekSets, _weekXP) {
  if (streak >= 30) return `${streak}日連続！この調子で今月の目標も超えていこう 🔥`;
  if (streak >= 14) return `2週間以上継続中。${weekSets}セットの積み重ねが体を変える 💪`;
  if (streak >= 7)  return `1週間継続達成！来週は ${weekSets + 1}セット以上を目指そう ✨`;
  if (weekSets >= 10) return `今週${weekSets}セット！運動習慣が定着してきた証拠だよ 🌟`;
  if (weekSets >= 5)  return `今週${weekSets}セット達成。明日もスクワット5回から始めよう 🏃`;
  if (weekSets > 0)   return `最初の一歩を踏み出した。次は${weekSets + 1}セットを目指そう 👟`;
  return '今週もFitingoを開いてくれてありがとう。明日の90秒から始めよう 🌱';
}

// ===== AI PROXY =====
// 「AI 機能は別途 API キー要」の廃止（docs/ai_proxy_plan.md 参照）。
// サーバー側の API キーで AI を代理呼び出しし、ユーザーには API キーの
// 概念を一切見せない。コストは月次クォータで管理する。
//
// クォータ（1ヶ月あたりの呼び出し回数）:
//   Free: 5 回（オンボーディングで「写真だけで記録」を体験させる）
//   Plus: 300 回
//
// API キーの設定（Secret Manager）:
//   firebase functions:secrets:set OPENAI_API_KEY
// Plus 判定:
//   users/{uid} ドキュメントの isPlus フィールド（iOS が購入時に書き込む）
// 日次・カテゴリ別クォータ
// 90秒モード中（activeDays < 5）: 全カテゴリ合計 1/日
// 5〜9日（Free）:               カテゴリ別 1/日
// 10日以降（Free）:              AI停止 → Plus誘導
// Plus:                         カテゴリ別 3/日
// カスタムAPIキー登録済み:        無制限（自己負担）
const AI_QUOTA = { ninety: 1, free: 1, plus: 3 };
const AI_FREE_MAX_DAYS = 10;  // これ以降は Free ユーザーの AI 利用停止
const AI_DEFAULT_MODEL = 'gpt-5.4-mini';

exports.aiProxy = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB', secrets: ['OPENAI_API_KEY'] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
    }
    const uid = context.auth.uid;
    const prompt = (data && data.prompt) || '';
    const imageBase64 = data && data.imageBase64;
    // category: 'food' | 'edu' | 'diet' | 'general'
    const category = (data && data.category) || 'general';
    // 90秒モード中か（activeDays < 5、クライアント申告）
    const isNinetyMode = !!(data && data.isNinetyMode);
    // 連続活動日数（クライアント申告: RetentionTracker.localActiveDayCount / getActiveDays().length）
    const activeDays = typeof (data && data.activeDays) === 'number' ? data.activeDays : 0;

    if (!prompt || typeof prompt !== 'string' || prompt.length > 8000) {
      throw new functions.https.HttpsError('invalid-argument', 'prompt が不正です');
    }

    // ── ユーザー情報取得（Plus 判定 + カスタム API キー）──────────
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    const isPlus = !!userData.isPlus;

    // カスタム API キー（Firestore: users/{uid}/settings.openaiApiKey）
    const settingsSnap = await db.collection('users').doc(uid)
      .collection('settings').doc('ai').get();
    const customApiKey = (settingsSnap.data() || {}).openaiApiKey || '';
    const usingCustomKey = customApiKey.length > 0;

    // ── 日次クォータチェック（カスタムキーがあれば無制限）────────
    const today = new Date().toISOString().slice(0, 10); // "2026-07-11"
    const usageRef = db.collection('users').doc(uid)
      .collection('ai-usage').doc(`daily-${today}`);

    if (!usingCustomKey) {
      const usageSnap = await usageRef.get();
      const usageData = usageSnap.data() || {};
      const catLabel = category === 'food' ? '食事AI' : category === 'edu' ? '語学AI' : 'AI';

      if (isNinetyMode) {
        // 90秒モード（0〜4日）: 全カテゴリ合計 1/日
        const totalToday = Object.entries(usageData)
          .filter(([k]) => k !== 'updatedAt')
          .reduce((sum, [, v]) => sum + (typeof v === 'number' ? v : 0), 0);
        if (totalToday >= AI_QUOTA.ninety) {
          throw new functions.https.HttpsError(
            'resource-exhausted',
            'QUOTA_NINETY|今日のAI枠を使いました。明日また試してね！\nAPIキーを登録すると何度でも使えます'
          );
        }
      } else if (!isPlus && activeDays >= AI_FREE_MAX_DAYS) {
        // 10日以降のFreeユーザー: AI停止 → Plus誘導
        throw new functions.https.HttpsError(
          'resource-exhausted',
          `QUOTA_REQUIRE_PLUS|${activeDays}日連続、すごい！\n${catLabel}をもっと使うには Fitingo Plus へ。\nPlusなら毎日3回使えます`
        );
      } else {
        // 5〜9日（Free: 1/日）または Plus（3/日）
        const categoryCount = usageData[category] || 0;
        const limit = isPlus ? AI_QUOTA.plus : AI_QUOTA.free;
        if (categoryCount >= limit) {
          const msg = isPlus
            ? `QUOTA_PLUS|今日の${catLabel}の上限（${limit}回）に達しました。明日またどうぞ！`
            : `QUOTA_FREE|今日の${catLabel}の無料枠（${limit}回）を使い切りました。\nPlusなら1日${AI_QUOTA.plus}回、APIキー登録で無制限に使えます`;
          throw new functions.https.HttpsError('resource-exhausted', msg);
        }
      }
    }

    // ── OpenAI 呼び出し ────────────────────────────────────────
    const apiKey = usingCustomKey ? customApiKey : process.env.OPENAI_API_KEY;
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
        max_completion_tokens: 1000,
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

    // 使用量を記録（カスタムキー使用時はカウントしない）
    if (!usingCustomKey) {
      await usageRef.set(
        {
          [category]: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    return { text, usingCustomKey, isPlus };
  });
