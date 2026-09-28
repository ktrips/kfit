// iOS アプリから書籍を開いたときの閲覧トークン（#bt=...）を扱う。
// トークンはサーバー（createBookToken）が uid と期限に署名したもので、
// 本文の取得（getBook）のたびにサーバーが検証する。ここでは保持と期限の確認だけを行う。

const KEY = 'fitingo_book_token';

/** URL の #bt= を sessionStorage に移し、URL からは消す（履歴やコピーに残さない） */
export function captureBookToken(): void {
  try {
    localStorage.removeItem('isPlus_secret'); // 廃止した ?plus=1 の名残を消す
    const m = window.location.hash.match(/[#&]bt=([A-Za-z0-9_\-.]+)/);
    if (!m) return;
    sessionStorage.setItem(KEY, m[1]);
    window.history.replaceState({}, '', window.location.pathname + window.location.search);
  } catch {
    // ストレージが使えない環境では何もしない（試し読みのまま）
  }
}

export function getBookToken(): string | null {
  try {
    const t = sessionStorage.getItem(KEY);
    if (!t) return null;
    const payload = JSON.parse(atob(t.split('.')[0].replace(/-/g, '+').replace(/_/g, '/')));
    if (typeof payload.exp !== 'number' || payload.exp < Date.now()) {
      sessionStorage.removeItem(KEY);
      return null;
    }
    return t;
  } catch {
    return null;
  }
}

export function hasBookToken(): boolean {
  return getBookToken() !== null;
}
