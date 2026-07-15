// Google は埋め込みWebView（LINE/Instagram/Facebook等のアプリ内ブラウザ）からの
// OAuthログインを "disallowed_useragent" としてブロックする。
// ログイン前にアプリ内ブラウザを検知し、外部ブラウザへの誘導を行うためのユーティリティ。

export type InAppBrowser = 'line' | 'instagram' | 'facebook' | 'other';

export function detectInAppBrowser(): InAppBrowser | null {
  const ua = navigator.userAgent || '';
  if (/\bLine\//i.test(ua)) return 'line';
  if (/Instagram/i.test(ua)) return 'instagram';
  if (/FBAN|FBAV|FB_IAB/i.test(ua)) return 'facebook';
  if (/MicroMessenger|TikTok|BytedanceWebview|KAKAOTALK/i.test(ua)) return 'other';
  return null;
}

export const IN_APP_BROWSER_LABEL: Record<InAppBrowser, string> = {
  line: 'LINE',
  instagram: 'Instagram',
  facebook: 'Facebook',
  other: 'このアプリ',
};

// LINEのアプリ内ブラウザは openExternalBrowser=1 を付与すると
// 端末の標準ブラウザで開き直してくれる（LINE固有の挙動）。
export function openInExternalBrowser(): void {
  const url = new URL(window.location.href);
  url.searchParams.set('openExternalBrowser', '1');
  window.location.href = url.toString();
}
