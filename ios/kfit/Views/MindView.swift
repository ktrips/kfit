import SwiftUI

struct MindView: View {
    @Binding var selectedTab: Int
    @StateObject private var healthKit = HealthKitManager.shared
    @Environment(\.openURL) private var openURL
    @State private var showMindfulnessSession = false
    @State private var showStretchSession = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection
                        currentStressCard
                        averageStressCard
                        suggestionsCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .task {
                if healthKit.isAvailable && !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                } else {
                    await healthKit.fetchAll()
                }
            }
            .refreshable {
                await healthKit.fetchAll()
            }
            .fullScreenCover(isPresented: $showMindfulnessSession) {
                MindfulnessSessionView { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(startDate: startDate, endDate: endDate)
                        if saved {
                            await healthKit.refreshMindfulness()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showStretchSession) {
                MindfulnessSessionView(
                    durationSeconds: 180,
                    title: "3分ストレッチ",
                    completedButtonTitle: "ストレッチを保存"
                ) { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 180
                        )
                        if saved {
                            await healthKit.refreshMindfulness()
                            await TimeSlotManager.shared.syncStretchFromHealthKit()
                        }
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ja_JP")
        dateFmt.dateFormat = "M/d(E)"
        let dateStr = dateFmt.string(from: Date())

        return ZStack {
            LinearGradient(
                colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 6) {
                // 左: Fitingoロゴ + Mindingo + 日付
                Image("mascot")
                    .resizable().scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                HStack(spacing: 0) {
                    Text("Mind").foregroundColor(Color(hex: "#58CC02"))
                    Text("ingo").foregroundColor(.white)
                }
                .font(.system(size: 12, weight: .black, design: .rounded))
                Text(dateStr)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))

                Spacer()

                // 右: HRV数値 + ステータスラベル
                if healthKit.isLoading {
                    ProgressView().tint(.white).scaleEffect(0.65)
                } else {
                    HStack(spacing: 5) {
                        if avgHRV > 0 {
                            Text("\(Int(avgHRV))")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        if stress.score >= 0 {
                            Text(stressStatusLabel(stress.score))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.20))
                                .cornerRadius(7)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .cornerRadius(12)
    }

    private func stressStatusLabel(_ score: Int) -> String {
        switch score {
        case ..<20: return "Great"
        case ..<40: return "Good"
        case ..<60: return "Normal"
        case ..<80: return "Low"
        default:    return "Bad"
        }
    }

    private var currentStressCard: some View {
        let stress = stressInfo(healthKit.latestHRV)
        return card {
            cardTitle("現在のストレス", icon: "heart.fill", color: stress.color)
            HStack(spacing: 10) {
                metricTile(label: "心拍数", value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—", unit: "bpm", color: Color(hex: "#FF4B4B"))
                metricTile(label: "HRV", value: healthKit.latestHRV > 0 ? "\(Int(healthKit.latestHRV))" : "—", unit: "ms", color: Color.duoGreen)
                stressTile(stress)
            }
            if stress.score >= 55 {
                suggestionBanner(
                    icon: "🫁",
                    text: "ストレスが高めです。マインドフルネスで深呼吸を1分だけ試してみましょう。",
                    color: stress.color
                )
            } else {
                suggestionBanner(
                    icon: "🌿",
                    text: "今の状態は落ち着いています。こまめな水分補給と短い休憩で維持しましょう。",
                    color: Color.duoGreen
                )
            }
            largeActionButton(
                icon: "🫁",
                title: "1分呼吸タイマー",
                subtitle: "Hapticに合わせて吸って・吐いて、完了後にHealthKitへ保存",
                color: Color(hex: "#1CB0F6")
            ) {
                showMindfulnessSession = true
            }
        }
    }

    private var averageStressCard: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        return card {
            cardTitle("1日の平均", icon: "waveform.path.ecg", color: stress.color)
            HStack(spacing: 10) {
                metricTile(label: "平均心拍", value: healthKit.todayAvgHeartRate > 0 ? "\(Int(healthKit.todayAvgHeartRate))" : "—", unit: "bpm", color: Color(hex: "#FF4B4B"))
                metricTile(label: "平均HRV", value: avgHRV > 0 ? "\(Int(avgHRV))" : "—", unit: "ms", color: Color.duoGreen)
                stressTile(stress)
            }
            Text(averageStressMessage(stress))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            largeActionButton(
                icon: "🤸",
                title: "3分ストレッチ",
                subtitle: "肩・首・背中をゆるめる3分セッションをHealthKitへ保存",
                color: Color.duoGreen
            ) {
                showStretchSession = true
            }
        }
    }

    private var suggestionsCard: some View {
        card {
            cardTitle("具体的にできること", icon: "sparkles", color: Color(hex: "#CE82FF"))
            VStack(spacing: 8) {
                ForEach(recommendations) { item in
                    recommendationRow(item)
                }
            }
        }
    }

    private func recommendationRow(_ item: MindRecommendation) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Text(item.prefix)
                .font(.system(size: 17))
            Text(item.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if item.actionType != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(item.color.opacity(0.6))
            }
        }
        .padding(10)
        .background(item.color.opacity(item.actionType != nil ? 0.14 : 0.10))
        .cornerRadius(12)

        if let action = item.actionType {
            return AnyView(
                Button {
                    handleRecommendationAction(action)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    private func handleRecommendationAction(_ action: String) {
        switch action {
        case "mindfulness":
            showMindfulnessSession = true
        case "fitness":
            selectedTab = 0
        case "intake":
            selectedTab = 3
        case "health":
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        default:
            break
        }
    }

    private var recommendations: [MindRecommendation] {
        let stress = stressInfo(healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV)
        var items: [MindRecommendation] = []

        if healthKit.todayMindfulnessMinutes < 1 {
            items.append(MindRecommendation(prefix: "🫁", text: "まだ深呼吸やマインドフルネスをしていません。1分だけ呼吸を整えてみましょう。", color: Color(hex: "#1CB0F6"), actionType: "mindfulness"))
        }
        if healthKit.todayMindfulnessSamples.filter({ $0.sessionTypeLabel == "Reflect" }).isEmpty {
            items.append(MindRecommendation(prefix: "🤸", text: "Reflectや軽いストレッチで、肩・首・背中をゆるめてみましょう。", color: Color.duoGreen, actionType: "mindfulness"))
        }
        if healthKit.todayStandHours < 6 || healthKit.todaySteps < 5000 {
            items.append(MindRecommendation(prefix: "🚶", text: "スタンド時間や歩数が少なめです。5分だけ外を歩く、階段を使うなどがおすすめです。", color: Color(hex: "#FF9600"), actionType: "health"))
        }
        if stress.score >= 55 {
            items.append(MindRecommendation(prefix: "💆", text: "こめかみ・首・肩を軽くマッサージして、体の緊張を落としてみましょう。", color: Color(hex: "#CE82FF"), actionType: "mindfulness"))
        }

        items.append(MindRecommendation(prefix: "☕", text: "コーヒーを淹れる、水を飲む、歯磨きをするなど、小さな切り替えを入れましょう。", color: Color(hex: "#1CB0F6"), actionType: "intake"))
        items.append(MindRecommendation(prefix: "🌤️", text: "遠くを見る、ぼおっとする、軽く息継ぎをするなど、いつもと違う休み方を試しましょう。", color: Color.duoGreen))
        items.append(MindRecommendation(prefix: "🍃", text: "息抜きの時間を予定に入れて、通知や画面から少し離れてみましょう。", color: Color.duoOrange))
        return Array(items.prefix(6))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func metricTile(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private func stressTile(_ stress: MindStressInfo) -> some View {
        VStack(spacing: 3) {
            Text("ストレス")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(stress.score >= 0 ? "\(stress.score)" : "—")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
            Text(stress.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(stress.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(stress.color.opacity(0.12))
        .cornerRadius(12)
    }

    private func suggestionBanner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private func largeActionButton(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: color.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func averageStressMessage(_ stress: MindStressInfo) -> String {
        switch stress.score {
        case ..<0: return "Apple HealthのHRVデータがまだありません。Apple Watchの計測後に更新されます。"
        case ..<30: return "平均ストレスは低めです。今のリズムを保ちながら、こまめに休憩しましょう。"
        case ..<55: return "平均ストレスは普通です。水分補給や短い散歩で整えていきましょう。"
        case ..<75: return "平均ストレスがやや高めです。深呼吸、軽いストレッチ、画面から離れる時間を作りましょう。"
        default: return "平均ストレスが高い状態です。無理せず休憩し、呼吸・散歩・マッサージで回復を優先しましょう。"
        }
    }

    private func stressInfo(_ hrv: Double) -> MindStressInfo {
        guard hrv > 0 else {
            return MindStressInfo(score: -1, label: "—", color: Color.duoSubtitle)
        }
        let score: Int = {
            if hrv >= 100 { return 5 }
            if hrv >= 80  { return Int(5  + (100 - hrv) / 20 * 10) }
            if hrv >= 60  { return Int(15 + (80  - hrv) / 20 * 20) }
            if hrv >= 40  { return Int(35 + (60  - hrv) / 20 * 25) }
            if hrv >= 20  { return Int(60 + (40  - hrv) / 20 * 20) }
            return Int(min(95, 80 + (20 - hrv) / 20 * 15))
        }()
        switch score {
        case ..<30: return MindStressInfo(score: score, label: "低い", color: Color.duoGreen)
        case ..<55: return MindStressInfo(score: score, label: "普通", color: Color(red: 0.4, green: 0.75, blue: 0.1))
        case ..<75: return MindStressInfo(score: score, label: "やや高", color: Color.duoOrange)
        default:    return MindStressInfo(score: score, label: "高い", color: Color(hex: "#FF4B4B"))
        }
    }
}

private struct MindStressInfo {
    let score: Int
    let label: String
    let color: Color
}

private struct MindRecommendation: Identifiable {
    let id = UUID()
    let prefix: String
    let text: String
    let color: Color
    var actionType: String? = nil  // "mindfulness" | "fitness" | "intake" | "health"
}
