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
                            refreshButton
                            activityCard
                            heartRateCard
                            hrvCard
                            sunlightCard
                            sleepCard
                            intakeCard
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

    // MARK: - リフレッシュボタン（目立たない）

    private var refreshButton: some View {
        Button {
            Task { await hk.fetchAll() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
                Text("データを更新")
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
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

    // MARK: - 心拍変動（HRV）カード

    private var hrvCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(icon: "waveform.circle.fill", label: "心拍変動（HRV）",
                      iconColor: Color(hex: "#FF6B6B"))

            if hk.latestHRV < 0.1 {
                Text("HRVデータがありません")
                    .font(.subheadline).foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 16) {
                    // 最新HRV
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#FF6B6B"))
                            Text("最新").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                            Spacer()
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", hk.latestHRV))
                                .font(.system(.title2, design: .rounded)).fontWeight(.black)
                                .foregroundColor(Color.duoDark)
                            Text("ms").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#FCE4EC"))
                    .cornerRadius(12)

                    // 今日の平均HRV
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#1CB0F6"))
                            Text("平均").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                            Spacer()
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", hk.todayAverageHRV))
                                .font(.system(.title2, design: .rounded)).fontWeight(.black)
                                .foregroundColor(Color.duoDark)
                            Text("ms").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#E3F2FD"))
                    .cornerRadius(12)
                }

                // HRVステータスバー
                let statusColor: Color = {
                    switch hk.hrvStatus {
                    case "良好": return Color.duoGreen
                    case "中程度": return Color(hex: "#FFD900")
                    default: return Color(hex: "#FF9600")
                    }
                }()
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text("ステータス:").font(.caption).foregroundColor(Color.duoSubtitle)
                    Text(hk.hrvStatus).font(.caption).fontWeight(.bold).foregroundColor(statusColor)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 日光露出カード

    private var sunlightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(icon: "sun.max.fill", label: "日光露出時間",
                      iconColor: Color(hex: "#FFD900"))

            if hk.todaySunlightExposure < 0.5 {
                Text("記録されたデータがありません")
                    .font(.subheadline).foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("屋外活動時間")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(formatSunlightMinutes(hk.todaySunlightExposure))
                                    .font(.system(.title2, design: .rounded))
                                    .fontWeight(.black)
                                    .foregroundColor(Color.duoDark)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#FFF3E0"))
                        .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("推奨値")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text("30 分")
                                    .font(.system(.title2, design: .rounded))
                                    .fontWeight(.black)
                                    .foregroundColor(Color.duoGreen)
                                Image(systemName: hk.todaySunlightExposure >= 30 ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .foregroundColor(hk.todaySunlightExposure >= 30 ? Color.duoGreen : Color.duoSubtitle)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#E8F5E9"))
                        .cornerRadius(12)
                    }

                    let progressPercent = min(hk.todaySunlightExposure / 30.0, 1.0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2)).frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#FFD900"), Color(hex: "#FF9600")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: progressPercent * 280, height: 8)
                    }

                    Text(sunlightStatusMessage())
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 睡眠カード

    private var sleepCard: some View {
        let sleepAnalysis = hk.analyzeSleepScore()

        return VStack(alignment: .leading, spacing: 16) {
            cardTitle(icon: "bed.double.fill", label: "昨夜の睡眠",
                      iconColor: Color(hex: "#CE82FF"))

            if hk.lastNightTotalHours < 0.1 {
                Text("昨夜の睡眠データがありません")
                    .font(.subheadline).foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // 睡眠スコアの大きな表示
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: CGFloat(sleepAnalysis.score) / 100.0)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "#CE82FF"), Color(hex: "#9C27B0")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 2) {
                                Text("\(sleepAnalysis.score)")
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundColor(Color.duoDark)
                                Text("点").font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        .frame(width: 100, height: 100)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("睡眠スコア")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)

                            Text(sleepAnalysis.rating)
                                .font(.title3).fontWeight(.black)
                                .foregroundColor(ratingColor(sleepAnalysis.rating))

                            HStack(spacing: 4) {
                                Text("評価:")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                                Text(sleepRatingDescription(sleepAnalysis.rating))
                                    .font(.caption).foregroundColor(Color.duoDark)
                            }

                            Spacer()
                        }

                        Spacer()
                    }
                }
                .padding(16)
                .background(Color(hex: "#F3E5F5"))
                .cornerRadius(14)

                // 睡眠時間タイル（2列）
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        sleepTile(
                            label: "合計睡眠",
                            value: formatHours(hk.lastNightTotalHours),
                            unit: "",
                            bg: Color(hex: "#E8EAED"),
                            accent: Color(hex: "#5F6368")
                        )
                        sleepTile(
                            label: "深い睡眠",
                            value: hk.lastNightDeepHours > 0.05
                                   ? formatHours(hk.lastNightDeepHours)
                                   : "—",
                            unit: "",
                            bg: Color(hex: "#BBDEFB"),
                            accent: Color(hex: "#1976D2")
                        )
                    }

                    HStack(spacing: 12) {
                        sleepTile(
                            label: "REM睡眠",
                            value: formatHours(sleepAnalysis.remHours),
                            unit: "",
                            bg: Color(hex: "#E1BEE7"),
                            accent: Color(hex: "#7B1FA2")
                        )
                        sleepTile(
                            label: "コア睡眠",
                            value: formatHours(sleepAnalysis.coreHours),
                            unit: "",
                            bg: Color(hex: "#C8E6C9"),
                            accent: Color(hex: "#388E3C")
                        )
                    }
                }

                // 大きな睡眠ステージバー
                if !hk.sleepSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("睡眠ステージの構成")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)

                        sleepStageBar
                            .frame(height: 32)

                        sleepStageLegendExpanded
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func sleepTile(label: String, value: String, unit: String = "", bg: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded)).fontWeight(.black)
                    .foregroundColor(accent)
                if !unit.isEmpty {
                    Text(unit).font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                }
            }
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
                HStack(spacing: 0) {
                    ForEach(hk.sleepSegments) { seg in
                        let w = max(1, geo.size.width * CGFloat(seg.durationHours / total))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: seg.stage.color))
                            .frame(width: w)
                    }
                }
            }
            .frame(height: 32)
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

    private var sleepStageLegendExpanded: some View {
        let stageDetails: [(stage: SleepSegment.SleepStage, label: String, hours: Double)] = {
            var hours: [SleepSegment.SleepStage: Double] = [:]
            for segment in hk.sleepSegments {
                hours[segment.stage, default: 0] += segment.durationHours
            }
            return [
                (.deep, "深い睡眠", hours[.deep] ?? 0),
                (.rem, "REM睡眠", hours[.rem] ?? 0),
                (.core, "コア睡眠", hours[.core] ?? 0),
                (.awake, "覚醒", hours[.awake] ?? 0),
            ]
        }()

        let total = stageDetails.reduce(0) { $0 + $1.hours }

        return VStack(spacing: 8) {
            ForEach(stageDetails, id: \.stage.rawValue) { stage, label, hours in
                if hours > 0 || stage == .awake {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: stage.color)).frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(Color.duoDark)
                            if hours > 0.01 {
                                Text("\(formatHours(hours))")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                        }

                        Spacer()

                        Text(String(format: "%.0f%%", (hours / max(total, 0.1)) * 100))
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color(hex: stage.color))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(hex: stage.color).opacity(0.08))
                    .cornerRadius(10)
                }
            }
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

    private func formatSunlightMinutes(_ minutes: Double) -> String {
        let mins = Int(minutes)
        if mins < 60 {
            return "\(mins)分"
        } else {
            let hours = mins / 60
            let remainMins = mins % 60
            return remainMins > 0 ? "\(hours)h \(remainMins)分" : "\(hours)時間"
        }
    }

    private func sunlightStatusMessage() -> String {
        if hk.todaySunlightExposure < 10 {
            return "日光を浴びる時間を増やしましょう"
        } else if hk.todaySunlightExposure < 30 {
            return "もう少し屋外活動を増やすと理想的です"
        } else {
            return "素晴らしい！十分な日光を浴びています"
        }
    }

    private func ratingColor(_ rating: String) -> Color {
        switch rating {
        case "最高": return Color(hex: "#00897B")
        case "良好": return Color(hex: "#388E3C")
        case "普通": return Color(hex: "#F57F17")
        case "要改善": return Color(hex: "#E64A19")
        default: return Color(hex: "#D32F2F")
        }
    }

    private func sleepRatingDescription(_ rating: String) -> String {
        switch rating {
        case "最高": return "素晴らしい睡眠質"
        case "良好": return "良好な睡眠"
        case "普通": return "平均的な睡眠"
        case "要改善": return "改善が必要"
        default: return "不十分な睡眠"
        }
    }

    // MARK: - 摂取データカード

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .foregroundColor(Color.duoOrange)
                Text("摂取データ").fontWeight(.black)
            }
            .font(.headline)
            .foregroundColor(Color.duoDark)

            VStack(spacing: 10) {
                // 摂取カロリー
                intakeRow(
                    icon: "flame.fill",
                    iconColor: Color.duoOrange,
                    label: "摂取カロリー",
                    value: hk.todayIntakeCalories,
                    unit: "kcal",
                    limit: 2500,
                    isReverse: false
                )

                Divider()

                // 水分
                intakeRow(
                    icon: "drop.fill",
                    iconColor: Color.duoBlue,
                    label: "水分",
                    value: hk.todayIntakeWater,
                    unit: "ml",
                    limit: 2000,
                    isReverse: false
                )

                Divider()

                // カフェイン
                intakeRow(
                    icon: "cup.and.saucer.fill",
                    iconColor: Color.duoBrown,
                    label: "カフェイン",
                    value: hk.todayIntakeCaffeine,
                    unit: "mg",
                    limit: 400,
                    isReverse: true
                )

                Divider()

                // アルコール
                intakeRow(
                    icon: "wineglass.fill",
                    iconColor: Color.duoPurple,
                    label: "アルコール",
                    value: hk.todayIntakeAlcohol,
                    unit: "g",
                    limit: 20,
                    isReverse: true
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private func intakeRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: Double,
        unit: String,
        limit: Double,
        isReverse: Bool
    ) -> some View {
        let percent = limit > 0 ? Int((value / limit) * 100) : 0
        let isOver = value > limit
        let isGood = isReverse ? !isOver : (value >= limit * 0.5)

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)

                if value > 0 {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", value))
                            .font(.title3).fontWeight(.black)
                            .foregroundColor(isOver && isReverse ? Color.red : (isGood ? Color.duoGreen : Color.duoDark))
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                    }
                } else {
                    Text("未記録")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
            }

            Spacer()

            // パーセンテージ表示
            if value > 0 {
                VStack(spacing: 2) {
                    Text("\(percent)%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(isOver && isReverse ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange))

                    if isOver && isReverse {
                        Text("過剰")
                            .font(.system(size: 9)).fontWeight(.bold)
                            .foregroundColor(Color.red)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((isOver && isReverse ? Color.red : (isGood ? Color.duoGreen : Color.duoOrange)).opacity(0.12))
                .cornerRadius(6)
            }
        }
    }
}

#Preview {
    NavigationView { HealthView() }
}
