import Foundation

// MARK: - 月曜始まりの週計算（共通化）
//
// TomoView / GoalView / GoalingoView に同じ「月曜始まりの週」計算が
// 微妙に異なる書き方で複数回実装されていたため、ここに集約する。
// self.firstWeekday の設定に関わらず、常に月曜始まりの結果を返す。

extension Calendar {
    /// 指定日を含む週の月曜日 0:00 を返す。
    func mondayStart(for date: Date) -> Date {
        var cal = self
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start)
        let daysFromMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: start) ?? start
    }
}
