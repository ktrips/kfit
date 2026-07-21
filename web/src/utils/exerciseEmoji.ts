// 種目名/ID → 絵文字の対応表。
// DashboardView / HistoryView / WeeklyGoalView に少しずつ違う内容・
// 一致方式でそれぞれ定義されていたのをここに統一する。

const EXERCISE_EMOJI: Record<string, string> = {
  'push-up': '💪', 'pushup': '💪',
  'squat': '🏋️',
  'sit-up': '🔥', 'situp': '🔥',
  'lunge': '🦵',
  'burpee': '⚡',
  'plank': '🧘',
};

/** 種目名/IDから絵文字を取得（部分一致、大文字小文字・スペース/ハイフン差異を無視） */
export function getExerciseEmoji(name: string): string {
  const key = (name ?? '').toLowerCase().replace(/\s+/g, '-');
  for (const [k, v] of Object.entries(EXERCISE_EMOJI)) {
    if (key.includes(k)) return v;
  }
  return '⚡';
}
