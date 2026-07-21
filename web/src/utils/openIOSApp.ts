// ローカルにインストール済みのkfit(Fitingo) iOSアプリをカスタムURLスキームで起動し、
// 起動できなかった場合（未インストール等）はApp Storeへフォールバックする。
//
// 重要: iOSアプリ側（Info.plist の CFBundleURLSchemes）に登録されているスキームは
// "fitingo" のみ。過去に "kfit://" を使っていた箇所は実際にはアプリを起動できず、
// 常にApp Storeへリダイレクトされていた（この関数で統一し修正）。
//
// FitingoDeepLink（kfitApp.swift/SharedAppComponents.swift）が認識するホスト名:
// workout / mindfulness / food / mind / goal / diet / record / home
export type FitingoDeepLinkHost =
  | 'workout' | 'mindfulness' | 'food' | 'mind' | 'goal' | 'diet' | 'record' | 'home';

/**
 * @param host        フィティンゴアプリ内で開きたい画面（省略時は home = デフォルトタブ）
 * @param fallbackURL アプリが開けなかった場合のフォールバック先（通常はApp Storeリンク）
 * @param fallbackDelayMs カスタムスキーム起動を試みてからフォールバックするまでの待機時間
 */
export function openIOSApp(
  fallbackURL: string,
  host: FitingoDeepLinkHost = 'home',
  fallbackDelayMs: number = 2000
): void {
  window.location.href = `fitingo://${host}`;
  setTimeout(() => {
    window.location.href = fallbackURL;
  }, fallbackDelayMs);
}
