#!/usr/bin/env node
/**
 * firstSetSeconds が未記録の原因を切り分けるための診断スクリプト。
 * 全ユーザーの profile（totalPoints/streak）と retention/summary
 * （firstActiveDay/firstSetSeconds）を突き合わせ、90秒モードの
 * 対象になり得たか・トレーニングで記録が始まったかを判定する。
 *
 * 判定ロジックは kfitApp.swift の initializeSimpleModeIfNeeded() /
 * RetentionTracker.recordFirstSetLatency() のクライアント側条件をそのまま反映:
 *   - isPreExistingUser = (totalPoints>0 || streak>0) && !hasRetentionData
 *     → true なら 90秒モード自体が一度も表示されない
 *   - firstActiveDay はトレーニング以外（食事/水分/マインドフルネス等）でも
 *     .timeSlotProgressDidSave で記録されるため、firstSetSeconds が無くても
 *     firstActiveDay だけはある = 90秒モードでトレーニング以外を先にやった
 *     か、90秒モード対象外で通常ダッシュボードから活動した、のどちらか。
 *
 * 実行方法:
 *   cd firebase/functions
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/check-retention-status.js
 */
const admin = require('firebase-admin');

admin.initializeApp();

function classify({ totalPoints, streak, hasRetentionData, firstSetSeconds }) {
  const isPreExistingUser = (totalPoints > 0 || streak > 0) && !hasRetentionData;
  if (isPreExistingUser) {
    return '🚫 既存ユーザー扱い → 90秒モード非表示（simpleModeEnabled=false）';
  }
  if (typeof firstSetSeconds === 'number') {
    return '✅ firstSetSeconds 記録済み';
  }
  if (hasRetentionData) {
    return '⚠️ 活動記録はあるがfirstSetSeconds未記録 → 初回行動がトレーニング以外(DIET/FOOD/EDU)だった可能性';
  }
  return '➖ 活動記録なし（未起動 or 未活動）';
}

async function main() {
  const usersSnap = await admin.firestore().collection('users').get();

  const rows = [];
  for (const userDoc of usersSnap.docs) {
    // profile（totalPoints/streak等）は users/{uid} ドキュメント直下に保存されている
    // （AuthenticationManager.loadUserProfile 参照）
    const profileData = userDoc.data() || {};

    const summarySnap = await userDoc.ref.collection('retention').doc('summary').get();
    const hasRetentionData = summarySnap.exists;
    const retentionData = hasRetentionData ? summarySnap.data() : {};

    const totalPoints = profileData.totalPoints ?? 0;
    const streak = profileData.streak ?? 0;
    const firstSetSeconds = retentionData.firstSetSeconds;
    const firstActiveDay = retentionData.firstActiveDay ?? '-';
    const totalActiveDays = retentionData.totalActiveDays ?? 0;
    const platforms = Object.keys(retentionData.platforms || {}).filter((k) => retentionData.platforms[k]);
    const firstPlatform = retentionData.firstPlatform ?? '-';
    const firstSource = retentionData.firstSource ?? '-';
    const firstReferrer = retentionData.firstReferrer ?? '-';

    rows.push({
      uid: userDoc.id,
      totalPoints,
      streak,
      hasRetentionData,
      firstActiveDay,
      totalActiveDays,
      firstSetSeconds,
      platforms,
      firstPlatform,
      firstSource,
      firstReferrer,
      status: classify({ totalPoints, streak, hasRetentionData, firstSetSeconds }),
    });
  }

  if (rows.length === 0) {
    console.log('users コレクションが空です。');
    return;
  }

  console.log(`\n=== 継続計測 診断結果（${rows.length}人）===\n`);
  for (const r of rows) {
    console.log(
      `${r.uid}\n` +
      `  totalPoints=${r.totalPoints} streak=${r.streak} ` +
      `firstActiveDay=${r.firstActiveDay} totalActiveDays=${r.totalActiveDays} ` +
      `firstSetSeconds=${r.firstSetSeconds ?? '(なし)'}\n` +
      `  platforms=[${r.platforms.join(', ') || '-'}] firstPlatform=${r.firstPlatform} ` +
      `firstSource=${r.firstSource} firstReferrer=${r.firstReferrer}\n` +
      `  → ${r.status}\n`
    );
  }

  const preExisting = rows.filter(r => r.status.startsWith('🚫')).length;
  const nonTraining = rows.filter(r => r.status.startsWith('⚠️')).length;
  const recorded = rows.filter(r => r.status.startsWith('✅')).length;
  const noActivity = rows.filter(r => r.status.startsWith('➖')).length;

  console.log('=== サマリー ===');
  console.log(`既存ユーザー除外: ${preExisting}人`);
  console.log(`活動はあるがトレーニング未計測: ${nonTraining}人`);
  console.log(`firstSetSeconds記録済み: ${recorded}人`);
  console.log(`活動記録なし: ${noActivity}人`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ 実行エラー:', err.message);
    process.exit(1);
  });
