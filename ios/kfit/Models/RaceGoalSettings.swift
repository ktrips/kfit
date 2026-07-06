import Foundation
import Combine

// MARK: - RaceGoalType

enum RaceGoalType: String, CaseIterable, Codable {
    case run10k        = "run10k"
    case halfMarathon  = "halfMarathon"
    case fullMarathon  = "fullMarathon"
    case olympicTri    = "olympicTri"
    case halfIronman   = "halfIronman"
    case fullIronman   = "fullIronman"
    case custom        = "custom"

    var displayName: String {
        switch self {
        case .run10k:       return "マラソン10km"
        case .halfMarathon: return "ハーフマラソン"
        case .fullMarathon: return "フルマラソン"
        case .olympicTri:   return "オリンピック・トライアスロン"
        case .halfIronman:  return "ハーフ・アイアンマン"
        case .fullIronman:  return "フル・アイアンマン"
        case .custom:       return "カスタム"
        }
    }

    var emoji: String {
        switch self {
        case .run10k, .halfMarathon, .fullMarathon: return "🏃"
        case .olympicTri, .halfIronman, .fullIronman: return "🏊"
        case .custom: return "🎯"
        }
    }

    var isTriathlon: Bool {
        switch self {
        case .olympicTri, .halfIronman, .fullIronman: return true
        default: return false
        }
    }

    // Official race distances
    var raceDistances: RaceDistances {
        switch self {
        case .run10k:       return RaceDistances(swimKm: 0,   bikeKm: 0,   runKm: 10.0)
        case .halfMarathon: return RaceDistances(swimKm: 0,   bikeKm: 0,   runKm: 21.0975)
        case .fullMarathon: return RaceDistances(swimKm: 0,   bikeKm: 0,   runKm: 42.195)
        case .olympicTri:   return RaceDistances(swimKm: 1.5, bikeKm: 40,  runKm: 10.0)
        case .halfIronman:  return RaceDistances(swimKm: 1.9, bikeKm: 90,  runKm: 21.1)
        case .fullIronman:  return RaceDistances(swimKm: 3.8, bikeKm: 180, runKm: 42.2)
        case .custom:       return RaceDistances(swimKm: 0,   bikeKm: 0,   runKm: 0)
        }
    }

    var distanceDescription: [String] {
        let d = raceDistances
        var result: [String] = []
        if d.swimKm > 0 { result.append("スイム \(formatKm(d.swimKm))km") }
        if d.bikeKm > 0 { result.append("バイク \(formatKm(d.bikeKm))km") }
        if d.runKm  > 0 { result.append("ラン \(formatKm(d.runKm))km") }
        return result
    }

    private func formatKm(_ km: Double) -> String {
        km == km.rounded() ? "\(Int(km))" : String(format: "%.4g", km)
    }
}

// MARK: - RaceDistances

struct RaceDistances: Codable {
    var swimKm: Double = 0
    var bikeKm: Double = 0
    var runKm:  Double = 0
}

// MARK: - RaceGoalSettings

struct RaceGoalSettings: Codable {
    var isEnabled: Bool = false
    var raceType: RaceGoalType = .olympicTri
    var raceDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    var customName:   String = ""
    var customSwimKm: Double = 0
    var customBikeKm: Double = 0
    var customRunKm:  Double = 0

    var effectiveDistances: RaceDistances {
        if raceType == .custom {
            return RaceDistances(swimKm: customSwimKm, bikeKm: customBikeKm, runKm: customRunKm)
        }
        return raceType.raceDistances
    }

    var weeksUntilRace: Int {
        let comps = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: raceDate)
        return max(0, comps.weekOfYear ?? 0)
    }

    var daysUntilRace: Int {
        let comps = Calendar.current.dateComponents([.day], from: Date(), to: raceDate)
        return max(0, comps.day ?? 0)
    }

    /// 週ごとの練習目標距離（大会に近づくほど増加）
    func weeklyTrainingGoal() -> RaceDistances {
        let base = effectiveDistances
        let weeks = weeksUntilRace
        let scale: Double
        switch weeks {
        case 0...4:   scale = 1.0   // ラスト1ヶ月：レース距離全量
        case 5...8:   scale = 0.8   // 2ヶ月前：80%
        case 9...12:  scale = 0.6   // 3ヶ月前：60%
        case 13...16: scale = 0.5   // 4ヶ月前：50%
        default:      scale = 0.4   // それ以前：40%
        }
        // 切り上げで刻み値に丸める
        func ceilTo(_ value: Double, step: Double) -> Double {
            guard step > 0, value > 0 else { return 0 }
            return ceil(value / step) * step
        }
        return RaceDistances(
            swimKm: ceilTo(base.swimKm * scale, step: 0.5),   // 0.5km刻み
            bikeKm: ceilTo(base.bikeKm * scale, step: 10.0),  // 10km刻み
            runKm:  ceilTo(base.runKm  * scale, step: 5.0)    // 5km刻み
        )
    }
}

// MARK: - RaceGoalManager

final class RaceGoalManager: ObservableObject {
    static let shared = RaceGoalManager()

    @Published var settings: RaceGoalSettings {
        didSet { save() }
    }

    private static let userDefaultsKey = "kfit_race_goal_settings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(RaceGoalSettings.self, from: data) {
            settings = decoded
        } else {
            settings = RaceGoalSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
