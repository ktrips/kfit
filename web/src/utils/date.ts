// ローカルタイムゾーンの日付キーユーティリティ
//
// iOS 側（TimeSlotManager / AuthenticationManager）は DateFormatter "yyyy-MM-dd"
// （端末ローカルタイムゾーン）で Firestore のドキュメント ID を生成する。
// Web 側で `toISOString().split('T')[0]` を使うと UTC 日付になり、
// JST では毎日 0:00〜8:59 の間、iOS と別の日付ドキュメントを読み書きしてしまう。
// 日付キーは必ずこのヘルパーを使うこと。

/** ローカルタイムゾーンの YYYY-MM-DD 文字列（iOS の dateString と互換） */
export function localDateKey(date: Date = new Date()): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
