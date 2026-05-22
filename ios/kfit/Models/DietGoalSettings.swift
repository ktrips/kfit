import Foundation

struct DietGoalSettings: Codable {
    var targetWeight: Double = 65.0
    var targetBodyFatPercent: Double = 15.0
    var hasBodyFatTarget: Bool = true
    var targetDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    var dailyIntakeGoal: Int = 2000
    var dailyBurnGoal: Int = 2200
    var startDate: Date = Date()
    var startWeight: Double = 0.0
    var startBodyFatPercent: Double = 0.0
    var hasStartStats: Bool = false

    var dailyDeficitGoal: Int { dailyIntakeGoal - dailyBurnGoal }
    var weeklyDeficitGoal: Int { dailyDeficitGoal * 7 }

    init(
        targetWeight: Double = 65.0,
        targetBodyFatPercent: Double = 15.0,
        hasBodyFatTarget: Bool = true,
        targetDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date(),
        dailyIntakeGoal: Int = 2000,
        dailyBurnGoal: Int = 2200,
        startDate: Date = Date(),
        startWeight: Double = 0.0,
        startBodyFatPercent: Double = 0.0,
        hasStartStats: Bool = false
    ) {
        self.targetWeight = targetWeight
        self.targetBodyFatPercent = targetBodyFatPercent
        self.hasBodyFatTarget = hasBodyFatTarget
        self.targetDate = targetDate
        self.dailyIntakeGoal = dailyIntakeGoal
        self.dailyBurnGoal = dailyBurnGoal
        self.startDate = startDate
        self.startWeight = startWeight
        self.startBodyFatPercent = startBodyFatPercent
        self.hasStartStats = hasStartStats
    }

    // 既存の保存データとの後方互換性（新フィールドがない場合はデフォルト値を使用）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetWeight         = (try? c.decode(Double.self, forKey: .targetWeight))         ?? 65.0
        targetBodyFatPercent = (try? c.decode(Double.self, forKey: .targetBodyFatPercent)) ?? 15.0
        hasBodyFatTarget     = (try? c.decode(Bool.self,   forKey: .hasBodyFatTarget))     ?? true
        targetDate           = (try? c.decode(Date.self,   forKey: .targetDate))
            ?? (Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
        dailyIntakeGoal      = (try? c.decode(Int.self,    forKey: .dailyIntakeGoal))      ?? 2000
        dailyBurnGoal        = (try? c.decode(Int.self,    forKey: .dailyBurnGoal))        ?? 2200
        startDate            = (try? c.decode(Date.self,   forKey: .startDate))            ?? Date()
        startWeight          = (try? c.decode(Double.self, forKey: .startWeight))          ?? 0.0
        startBodyFatPercent  = (try? c.decode(Double.self, forKey: .startBodyFatPercent))  ?? 0.0
        hasStartStats        = (try? c.decode(Bool.self,   forKey: .hasStartStats))        ?? false
    }

    static let userDefaultsKey = "kfit_diet_goal_settings"
}

// MARK: - DietGoalManager

final class DietGoalManager: ObservableObject {
    static let shared = DietGoalManager()

    @Published var settings: DietGoalSettings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: DietGoalSettings.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(DietGoalSettings.self, from: data) {
            settings = decoded
        } else {
            settings = DietGoalSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: DietGoalSettings.userDefaultsKey)
        }
    }
}
