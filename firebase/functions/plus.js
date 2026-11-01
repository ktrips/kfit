// Fitingo Plus の判定をサーバー側で一元管理する。
//
// これまでは iOS アプリが users/{uid}.isPlus を自分で書き込んでいたため、
// 課金せずに Plus を有効化できてしまった。現在は次の 3 つだけが Plus の根拠になる。
//   1. App Store の購入（署名付き取引をサーバーで検証したもの）
//   2. 管理者が付与したプロモ（無料の Plus ユーザー）
//   3. 管理者本人
// users/{uid} の isPlus / plusSource / plusAppStore / plusPromo はサーバーだけが書き込む
// （firestore.rules でクライアントからの書き込みを禁止している）。

const fs = require('fs');
const path = require('path');
const functions = require('firebase-functions');
const admin = require('firebase-admin');

const db = admin.firestore();

const ADMIN_EMAIL = 'kenichiyoshida13@gmail.com';
const BUNDLE_ID = 'com.kfitappduo.app';
const PRODUCT_IDS = ['fitingo_plus_monthly', 'fitingo_plus_yearly'];
// App Store Connect の「一般 > App 情報 > Apple ID」（数字）。本番環境の署名検証に必要。
// firebase/functions/.env に APP_APPLE_ID=1234567890 の形で設定する。
const APP_APPLE_ID = Number(process.env.APP_APPLE_ID || 0) || undefined;

let verifiers = null;
function getVerifiers() {
  if (verifiers) return verifiers;
  // Apple のライブラリと証明書は購入の検証時だけ読み込む（index.js 経由で全関数がこの
  // ファイルを読むため、先頭で読み込むと AI やポイント計算などの起動まで遅くなる）
  const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');
  const ROOT_CERTS = ['AppleRootCA-G3.cer', 'AppleRootCA-G2.cer']
    .map((f) => fs.readFileSync(path.join(__dirname, 'certs', f)));
  verifiers = [];
  if (APP_APPLE_ID) {
    verifiers.push(new SignedDataVerifier(ROOT_CERTS, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID));
  }
  // TestFlight と開発ビルドの購入は Sandbox
  verifiers.push(new SignedDataVerifier(ROOT_CERTS, true, Environment.SANDBOX, BUNDLE_ID));
  return verifiers;
}

/** 署名付きデータを本番 → Sandbox の順で検証する。どれでも検証できなければ例外 */
async function verifyWithAny(fn) {
  let lastError = null;
  for (const v of getVerifiers()) {
    try {
      return await fn(v);
    } catch (e) {
      lastError = e;
    }
  }
  if (!APP_APPLE_ID) {
    console.warn('[plus] APP_APPLE_ID が未設定のため本番の購入は検証できません');
  }
  throw lastError || new Error('verification failed');
}

function toMillis(ts) {
  if (!ts) return null;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  return Number(ts) || null;
}

function isAdminEmail(email) {
  return (email || '').toLowerCase() === ADMIN_EMAIL.toLowerCase();
}

/** ユーザードキュメントから現在の Plus 状態を判定する（期限も見る） */
function plusStatusFromData(userData, email) {
  const now = Date.now();
  if (isAdminEmail(email)) return { isPlus: true, source: 'admin', expiresAt: null };

  const promo = userData.plusPromo;
  if (promo && promo.enabled) {
    const exp = toMillis(promo.expiresAt);
    if (!exp || exp > now) return { isPlus: true, source: 'promo', expiresAt: exp };
  }
  const store = userData.plusAppStore;
  if (store && !store.revoked) {
    const exp = toMillis(store.expiresAt);
    if (exp && exp > now) return { isPlus: true, source: 'appstore', expiresAt: exp };
  }
  return { isPlus: false, source: null, expiresAt: null };
}

async function emailOf(uid) {
  try {
    return (await admin.auth().getUser(uid)).email || '';
  } catch (_e) {
    return '';
  }
}

/** 判定し直して users/{uid} の isPlus / plusSource を更新する */
async function recomputePlus(uid) {
  const ref = db.collection('users').doc(uid);
  const [snap, email] = await Promise.all([ref.get(), emailOf(uid)]);
  const status = plusStatusFromData(snap.data() || {}, email);
  await ref.set({
    isPlus: status.isPlus,
    plusSource: status.source,
    plusCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return status;
}

function statusResponse(status) {
  return { isPlus: status.isPlus, source: status.source, expiresAt: status.expiresAt };
}

/** 検証済みの取引を uid に結び付ける。同じ購入を別アカウントで使っていた場合は移す */
async function applyTransaction(uid, tx, environment) {
  const otid = tx.originalTransactionId;
  const subRef = db.collection('plusSubscriptions').doc(otid);
  const prev = await subRef.get();
  const prevUid = prev.exists ? prev.data().uid : null;

  const record = {
    productId: tx.productId,
    originalTransactionId: otid,
    expiresAt: tx.expiresDate ? admin.firestore.Timestamp.fromMillis(tx.expiresDate) : null,
    revoked: !!tx.revocationDate,
    environment: environment || null,
    verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await subRef.set({ uid, ...record }, { merge: true });
  await db.collection('users').doc(uid).set({ plusAppStore: record }, { merge: true });

  if (prevUid && prevUid !== uid) {
    // 1 つの購入を複数アカウントで同時に使えないよう、以前のアカウントからは外す
    const prevRef = db.collection('users').doc(prevUid);
    const prevSnap = await prevRef.get();
    if ((prevSnap.data() || {}).plusAppStore?.originalTransactionId === otid) {
      await prevRef.update({ plusAppStore: admin.firestore.FieldValue.delete() });
      await recomputePlus(prevUid);
    }
  }
}

// ── 購入の検証（iOS から呼ぶ）────────────────────────────────────────
// data.signedTransactions: StoreKit 2 の VerificationResult.jwsRepresentation の配列
// 空配列でも呼べる（現在の Plus 状態の再判定だけを行う）
exports.verifySubscription = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
    }
    const uid = context.auth.uid;
    const list = Array.isArray(data && data.signedTransactions) ? data.signedTransactions.slice(0, 10) : [];

    let best = null;
    for (const jws of list) {
      if (typeof jws !== 'string' || jws.length > 20000) continue;
      try {
        const tx = await verifyWithAny((v) => v.verifyAndDecodeTransaction(jws));
        if (!PRODUCT_IDS.includes(tx.productId) || !tx.originalTransactionId) continue;
        if (!best || (tx.expiresDate || 0) > (best.expiresDate || 0)) best = tx;
      } catch (e) {
        console.warn('[verifySubscription] invalid transaction', uid, e.message || e);
      }
    }
    if (best) await applyTransaction(uid, best, best.environment);
    return statusResponse(await recomputePlus(uid));
  });

// ── プロモ（無料の Plus ユーザー）の付与・解除：管理者のみ ────────────────
function assertAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
  }
  const token = context.auth.token || {};
  // クライアント申告ではなく、検証済み ID トークンのメールだけを信頼する
  if (!isAdminEmail(token.email) || token.email_verified !== true) {
    throw new functions.https.HttpsError('permission-denied', 'この操作は管理者のみ実行できます');
  }
}

// data: { email: string, enabled: boolean, days?: number（省略・0 は無期限）, note?: string }
exports.setPromoUser = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data, context) => {
    assertAdmin(context);
    const email = String((data && data.email) || '').trim().toLowerCase();
    if (!email || !email.includes('@') || email.length > 200) {
      throw new functions.https.HttpsError('invalid-argument', 'メールアドレスが不正です');
    }
    const enabled = !!(data && data.enabled);
    const days = Number((data && data.days) || 0);
    if (!Number.isFinite(days) || days < 0 || days > 3650) {
      throw new functions.https.HttpsError('invalid-argument', '日数は0〜3650で指定してください');
    }

    let target;
    try {
      target = await admin.auth().getUserByEmail(email);
    } catch (_e) {
      throw new functions.https.HttpsError('not-found',
        'このメールのユーザーが見つかりません（先に Fitingo へ一度ログインしてもらってください）');
    }

    const ref = db.collection('users').doc(target.uid);
    if (enabled) {
      await ref.set({
        plusPromo: {
          enabled: true,
          expiresAt: days > 0 ? admin.firestore.Timestamp.fromMillis(Date.now() + days * 86400000) : null,
          grantedBy: context.auth.token.email,
          grantedAt: admin.firestore.FieldValue.serverTimestamp(),
          note: String((data && data.note) || '').slice(0, 200),
        },
      }, { merge: true });
    } else {
      await ref.set({ plusPromo: admin.firestore.FieldValue.delete() }, { merge: true });
    }
    const status = await recomputePlus(target.uid);
    console.log('[setPromoUser]', context.auth.token.email, enabled ? 'grant' : 'revoke', email, days);
    return { email, uid: target.uid, ...statusResponse(status) };
  });

exports.listPromoUsers = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (_data, context) => {
    assertAdmin(context);
    const snap = await db.collection('users').where('plusPromo.enabled', '==', true).limit(200).get();
    const rows = await Promise.all(snap.docs.map(async (doc) => {
      const p = doc.data().plusPromo || {};
      return {
        uid: doc.id,
        email: await emailOf(doc.id),
        expiresAt: toMillis(p.expiresAt),
        grantedAt: toMillis(p.grantedAt),
        note: p.note || '',
      };
    }));
    rows.sort((a, b) => (b.grantedAt || 0) - (a.grantedAt || 0));
    return { users: rows };
  });

// ── App Store Server Notifications V2 ─────────────────────────────────
// App Store Connect の「App 情報 > App Store サーバ通知」にこの関数の URL を登録すると、
// 更新・返金・期限切れがアプリを開かなくても反映される。
exports.appStoreNotifications = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    try {
      const signedPayload = req.body && req.body.signedPayload;
      if (typeof signedPayload !== 'string') {
        res.status(400).send('bad request');
        return;
      }
      const notification = await verifyWithAny((v) => v.verifyAndDecodeNotification(signedPayload));
      const signedTx = notification.data && notification.data.signedTransactionInfo;
      if (!signedTx) {
        res.status(200).send('ok');
        return;
      }
      const tx = await verifyWithAny((v) => v.verifyAndDecodeTransaction(signedTx));
      const sub = await db.collection('plusSubscriptions').doc(tx.originalTransactionId).get();
      if (sub.exists && PRODUCT_IDS.includes(tx.productId)) {
        const uid = sub.data().uid;
        const type = notification.notificationType;
        const revoked = !!tx.revocationDate || type === 'REFUND' || type === 'REVOKE';
        await applyTransaction(uid, { ...tx, revocationDate: revoked ? (tx.revocationDate || Date.now()) : null },
          tx.environment);
        await recomputePlus(uid);
        console.log('[appStoreNotifications]', type, notification.subtype || '', uid);
      }
      res.status(200).send('ok');
    } catch (e) {
      console.error('[appStoreNotifications] error', e.message || e);
      // 検証できない通知は受け付けない（Apple は 200 以外を再送する）
      res.status(400).send('invalid');
    }
  });

// ── 期限切れの反映（毎日）────────────────────────────────────────────
exports.expirePlusDaily = functions.pubsub
  .schedule('every day 04:30')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const snap = await db.collection('users').where('isPlus', '==', true).limit(2000).get();
    let expired = 0;
    for (const doc of snap.docs) {
      const email = await emailOf(doc.id);
      const status = plusStatusFromData(doc.data(), email);
      if (!status.isPlus) {
        await doc.ref.set({ isPlus: false, plusSource: null,
          plusCheckedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        expired++;
      }
    }
    console.log(`[expirePlusDaily] checked=${snap.size} expired=${expired}`);
    return null;
  });

exports.plusStatusFromData = plusStatusFromData;
