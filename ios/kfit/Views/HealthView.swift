import SwiftUI
import HealthKit

// MARK: - HealthView

struct HealthView: View {
    @StateObject private var hk = HealthKitManager.shared

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            if !hk.isAvailable {
                unavailableState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection

                        if !hk.isAuthorized {
                            authCard
                        } else if hk.isLoading {
                            loadingCard
                        } else {
                            activityCard
                            heartRateCard
                            sleepCard
                            if !hk.hrSamples.isEmpty { hrHistoryCard }
                            openHealthButton
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await hk.fetchAll() }
            }
        }
        .navigationTitle("健康データ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hk.refreshAuthorizationStatus()
            if hk.isAuthorized {
                await hk.fetchAll()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#FF6B6B"), Color(hex: "#FF4B4B")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("健康データ")
                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                Text("Apple Healthから取得")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - HealthKit 非対応

    private var unavailableState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: 56))
                .foregroundColor(Color.duoSubtitle)
            Text("HealthKitは非対応です")
                .font(.headline).fontWeight(.black)
                .foregroundColor(Color.duoDark)
            Text("このデバイスではApple Healthが使用できません")
                .font(.subheadline).foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - 権限未取得

    private var authCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "#FF4B4B"))

            Text("Apple Healthと連動する")
                .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)

            Text("心拍数・歩数・消費カロリー・睡眠データをHealthKitから取得します。データは端末内にのみ保存されます。")
                .font(.subheadline).foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    ("heart.fill",    "心拍数・安静時心拍数"),
                    ("figure.walk",   "歩数"),
                    ("flame.fill",    "消費カロリー"),
                    ("bed.double.fill","睡眠（時間・ステージ）"),
                ], id: \.0) { icon, label in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(Color.duoGreen)
                            .frame(width: 24)
                        Text(label)
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(Color.duoDark)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(12)

            Button {
                Task { await hk.requestAuthorization() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Healthと連動する")
                        .fontWeight(.black)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "#FF4B4B"))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - ローディング

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(Color(hex: "#FF4B4B"))
            Text("HealthKitからデータを取得中...")
                .font(.subheadline).foregroundColor(Color.duoSubtitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(14)
    }

    // MARK: - アクティビティカード（歩数・カロリー）

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(icon: "figure.walk", label: "今日のアクティビティ",
                      iconColor: Color.duoGreen)

            HStack(spacing: 12) {
                activityTile(
                    icon: "figure.walk",
                    color: Color.duoGreen,
                    value: "\(hk.todaySteps.formatted())",
                    unit: "歩",
                    bg: Color(hex: "#D7FFB8")
                )
                activityTile(
                    icon: "flame.fill",
                    color: Color(hex: "#FF9600"),
                    value: "\(Int(hk.todayCalories))",
                    unit: "kcal",
                    bg: Color(hex: "#FFF3E0")
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func activityTile(icon: String, color: Color, value: String, unit: String, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Text(unit)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(12)
    }

    // MARK: - 心拍数カード

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(icon: "heart.fill", label: "心拍数",
                      iconColor: Color(hex: "#FF4B4B"))

            HStack(spacing: 12) {
                // 最新心拍
                heartRateTile(
                    label: "最新",
                    value: hk.latestHeartRate > 0 ? "\(Int(hk.latestHeartRate))" : "—",
                    unit: "bpm",
                    icon: "heart.fill",
                    bg: Color(hex: "#FCE4EC"),
                    accent: Color(hex: "#FF4B4B")
                )
                // 安静時心拍
                heartRateTile(
                    label: "安静時",
                    value: hk.restingHeartRate > 0 ? "\(Int(hk.restingHeartRate))" : "—",
                    unit: "bpm",
                    icon: "bed.double.fill",
                    bg: Color(hex: "#E3F2FD"),
                    accent: Color(hex: "#1CB0F6")
                )
            }

            // 心拍ゾーン判定
            if hk.latestHeartRate > 0 {
                hrZoneBanner(bpm: hk.latestHeartRate)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func heartRateTile(label: String, value: String, unit: String,
                                icon: String, bg: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.subheadline).foregroundColor(accent)
                Text(label).font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded)).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                if value != "—" {
                    Text(unit).font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(12)
    }

    private func hrZoneBanner(bpm: Double) -> some View {
        let (zone, color, desc) = heartRateZone(bpm: bpm)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text("ゾーン \(zone)").font(.caption).fontWeight(.black).foregroundColor(color)
            Text("— \(desc)").font(.caption).foregroundColor(Color.duoSubtitle)
            Spacer()
            Text("\(Int(bpm)) bpm").font(.caption).fontWeight(.bold).foregroundColor(Color.duoDark)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }

    private func heartRateZone(bpm: Double) -> (zone: Int, color: Color, desc: String) {
        switch bpm {
        case ..<90:   return (1, Color(hex: "#58CC02"),  "リラックス")
        case ..<110:  return (2, Color(hex: "#1CB0F6"),  "軽い運動")
        case ..<130:  return (3, Color(hex: "#FFD900"),  "有酸素")
        case ..<150:  return (4, Color(hex: "#FF9600"),  "無酸素閾値")
        default:      return (5, Color(hex: "#FF4B4B"),  "最大強度")
        }
    }

    // MARK: - 睡眠カード

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(icon: "bed.double.fill", label: "昨夜の睡眠",
                      iconColor: Color(hex: "#CE82FF"))

            if hk.lastNightTotalHours < 0.1 {
                Text("昨夜の睡眠データがありません")
                    .font(.subheadline).foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                // 合計・深い睡眠
                HStack(spacing: 12) {
                    sleepTile(
                        label: "合計睡眠",
                        value: formatHours(hk.lastNightTotalHours),
                        bg: Color(hex: "#F3E5F5"),
                        accent: Color(hex: "#CE82FF")
                    )
                    sleepTile(
                        label: "深い睡眠",
                        value: hk.lastNightDeepHours > 0.05
                               ? formatHours(hk.lastNightDeepHours)
                               : "—",
                        bg: Color(hex: "#E3F2FD"),
                        accent: Color(hex: "#1CB0F6")
                    )
                }

                // 睡眠ステージバー
                if !hk.sleepSegments.isEmpty {
                    sleepStageBar
                    sleepStageLegend
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func sleepTile(label: String, value: String, bg: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(.title2, design: .rounded)).fontWeight(.black)
                .foregroundColor(Color.duoDark)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(12)
    }

    private var sleepStageBar: some View {
        let total = hk.sleepSegments.reduce(0.0) { $0 + $1.durationHours }
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(hk.sleepSegments) { seg in
                        let w = max(2, geo.size.width * CGFloat(seg.durationHours / total))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: seg.stage.color))
                            .frame(width: w, height: 20)
                    }
                }
            }
            .frame(height: 20)
        )
    }

    private var sleepStageLegend: some View {
        let stages: [(SleepSegment.SleepStage, String)] = [
            (.deep,    "深い睡眠"),
            (.rem,     "REM"),
            (.core,    "コア"),
            (.awake,   "覚醒"),
        ]
        return HStack(spacing: 12) {
            ForEach(stages, id: \.0.rawValue) { stage, label in
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: stage.color)).frame(width: 8, height: 8)
                    Text(label).font(.system(size: 10)).foregroundColor(Color.duoSubtitle)
                }
            }
            Spacer()
        }
    }

    // MARK: - 心拍履歴カード

    private var hrHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle(icon: "waveform.path.ecg", label: "今日の心拍履歴",
                      iconColor: Color(hex: "#FF4B4B"))

            VStack(spacing: 0) {
                ForEach(Array(hk.hrSamples.prefix(10).enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 12) {
                        Text(timeFmt.string(from: s.date))
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .frame(width: 44, alignment: .leading)

                        // Mini bar
                        GeometryReader { g in
                            let maxBPM: Double = 200
                            let barW = g.size.width * min(s.bpm / maxBPM, 1.0)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray6)).frame(height: 6)
                                Capsule()
                                    .fill(heartRateZone(bpm: s.bpm).color)
                                    .frame(width: barW, height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(Int(s.bpm)) bpm")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(heartRateZone(bpm: s.bpm).color)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    if idx < min(hk.hrSamples.count, 10) - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Healthアプリを開くボタン

    private var openHealthButton: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .foregroundColor(Color(hex: "#FF4B4B"))
                Text("Healthアプリで詳細を見る")
                    .fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func cardTitle(icon: String, label: String, iconColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline).foregroundColor(iconColor)
            Text(label).font(.subheadline).fontWeight(.black).foregroundColor(Color.duoDark)
        }
    }

    private func formatHours(_ h: Double) -> String {
        let total = Int(h * 60)
        return "\(total / 60)h \(total % 60)m"
    }
}

#Preview {
    NavigationView { HealthView() }
}
