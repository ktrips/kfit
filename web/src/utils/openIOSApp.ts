// ローカルにインストール済みのkfit(Fitingo) iOSアプリをカスタムURLスキームで起動し、
// 起動できなかった場合（未インストール等）はフォールバック先へ遷移する。
//
// 重要: iOSアプリ側（Info.plist の CFBundleURLSchemes）に登録されているスキームは
// "fitingo" のみ。過去に "kfit://" を使っていた箇所は実際にはアプリを起動できず、
// 常にフォールバック先へリダイレクトされていた（この関数で統一し修正）。
//
// FitingoDeepLink（kfitApp.swift/SharedAppComponents.swift）が認識するホスト名:
// workout / mindfulness / food / mind / goal / diet / record / home
export type FitingoDeepLinkHost =
  | 'workout' | 'mindfulness' | 'food' | 'mind' | 'goal' | 'diet' | 'record' | 'home';

// App Store未公開（2026-07時点ではTestFlight配布のみ）のため、
// フォールバック先は暫定的にTestFlightの公開リンクを使用する。
// App Store公開後はこの値をApp StoreのURLに差し替える。
export const IOS_DOWNLOAD_URL = 'https://testflight.apple.com/join/hdaA3QWP';

/**
 * @param host        フィティンゴアプリ内で開きたい画面（省略時は home = デフォルトタブ）
 * @param fallbackURL アプリが開けなかった場合のフォールバック先（通常はIOS_DOWNLOAD_URL）
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
