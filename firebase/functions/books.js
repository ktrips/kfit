// 有料書籍の本文をサーバーから配信する。
//
// これまでは全文の Markdown を web/public/books/ に公開ファイルとして置き、画面側で
// 試し読みに切り詰めていたため、URL を直接開けば誰でも全文を読めた。また Web は
// URL に ?plus=1 を付けるだけで Plus 扱いになっていた。
// 現在は Plus（plus.js の判定）の場合だけ全文を返し、それ以外は試し読み分だけを返す。
//
// 判定の根拠:
//   - Web で Fitingo にログインしている → そのアカウントの Plus 状態
//   - iOS アプリから開いた → createBookToken が発行した短時間のトークン（uid と期限に署名）

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { plusStatusFromData } = require('./plus');

const db = admin.firestore();

const PAID_BOOKS = ['apple-watch-diet', 'cursor-claude-code', 'cursor-claude-code-plus'];
const FREE_CHAR_LIMIT = 8000; // web/src/components/books/BookViewer.tsx と同じ
const TOKEN_TTL_MS = 2 * 60 * 60 * 1000;

function readBook(bookId) {
  return fs.readFileSync(path.join(__dirname, 'books', `${bookId}.md`), 'utf8');
}

/** 試し読み分: FREE_CHAR_LIMIT 以降で最初の ## 見出しの手前まで */
function preview(content) {
  if (content.length <= FREE_CHAR_LIMIT) return content;
  const idx = content.indexOf('\n## ', FREE_CHAR_LIMIT);
  return idx !== -1 ? content.slice(0, idx) : content.slice(0, FREE_CHAR_LIMIT);
}

function sign(payload) {
  const secret = process.env.BOOK_TOKEN_SECRET;
  if (!secret) throw new Error('BOOK_TOKEN_SECRET is not set');
  return crypto.createHmac('sha256', secret).update(payload).digest('base64url');
}

function makeToken(uid) {
  const payload = Buffer.from(JSON.stringify({ uid, exp: Date.now() + TOKEN_TTL_MS })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

/** 正しく署名され期限内なら uid を返す */
function readToken(token) {
  if (typeof token !== 'string' || token.length > 500) return null;
  const [payload, sig] = token.split('.');
  if (!payload || !sig) return null;
  const expected = sign(payload);
  if (sig.length !== expected.length ||
      !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  try {
    const { uid, exp } = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return typeof uid === 'string' && exp > Date.now() ? uid : null;
  } catch (_e) {
    return null;
  }
}

async function isPlusUid(uid, email) {
  const snap = await db.collection('users').doc(uid).get();
  let mail = email;
  if (mail === undefined) {
    try { mail = (await admin.auth().getUser(uid)).email || ''; } catch (_e) { mail = ''; }
  }
  return plusStatusFromData(snap.data() || {}, mail).isPlus;
}

// iOS アプリ（ログイン済み）から Web の書籍を開くときの短時間トークン
exports.createBookToken = functions
  .runWith({ timeoutSeconds: 15, memory: '128MB', secrets: ['BOOK_TOKEN_SECRET'] })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ログインが必要です');
    }
    if (!(await isPlusUid(context.auth.uid, context.auth.token.email))) {
      throw new functions.https.HttpsError('permission-denied', 'Plus 会員のみ利用できます');
    }
    return { token: makeToken(context.auth.uid), expiresInMs: TOKEN_TTL_MS };
  });

// data: { bookId, token? }  → { content, full }
exports.getBook = functions
  .runWith({ timeoutSeconds: 15, memory: '256MB', secrets: ['BOOK_TOKEN_SECRET'] })
  .https.onCall(async (data, context) => {
    const bookId = String((data && data.bookId) || '');
    if (!PAID_BOOKS.includes(bookId)) {
      throw new functions.https.HttpsError('not-found', '書籍が見つかりません');
    }
    let full = false;
    if (context.auth) {
      full = await isPlusUid(context.auth.uid, context.auth.token.email);
    }
    if (!full && data && data.token) {
      const uid = readToken(data.token);
      if (uid) full = await isPlusUid(uid);
    }
    const content = readBook(bookId);
    return { content: full ? content : preview(content), full };
  });

