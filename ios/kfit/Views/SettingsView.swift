import SwiftUI
import UserNotifications

// MARK: - 毎日の設定モデル → Models/DailyFixedGoals.swift に移動

// MARK: - 曜日毎の目標モデル

struct WeekdayCustomGoal: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    init(name: String, emoji: String) { self.id = UUID(); self.name = name; self.emoji = emoji }
}

struct WeekdayGoal: Codable, Identifiable, Equatable {
    let weekday: Int // 1=月 … 7=日
    var exerciseEnabled: Bool = false    // 🏃 アクティビティリング完了（自動）
    var studyEnabled: Bool = false       // 📚 勉強（手動）
    var noAlcoholEnabled: Bool = false   // 🚫 禁酒（手動）
    var customGoals: [WeekdayCustomGoal] = []
    var id: Int { weekday }
    static let labels = ["月", "火", "水", "木", "金", "土", "日"]
    var label: String { Self.labels[weekday - 1] }
    var hasAnyGoal: Bool { exerciseEnabled || studyEnabled || noAlcoholEnabled || !customGoals.isEmpty }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Binding var selectedTab: Int
    @StateObject private var notif = NotificationManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @StateObject private var dietGoalManager = DietGoalManager.shared
    @StateObject private var plus = PlusManager.shared
    @State private var showPlusView = false
    @State private var watchAutoLaunch = iOSWatchBridge.isWatchAutoLaunchEnabled
    @State private var permStatus: UNAuthorizationStatus = .notDetermined
    @State private var showHabitStack = false
    @State private var showHabitSettings = false
    @State private var showRaceGoalSettings = false
    @State private var showTimeSlotGoals = false
    @State private var showShortcutsGuide = false
    @State private var showAdvancedSettings = false
    @State private var savedBanner = false
    @State private var setConfiguration = SetConfiguration.defaultSet
    @State private var motionSensitivity: [String: MotionSensitivity] = MotionSensitivity.defaultSettings
    @State private var showSensitivityEditor = false
    @State private var showIntakeSettings = false
    @State private var showDietGoalSettings = false
    @State private var showLLMSettings = false
    @State private var showAPIKeySheet = false
    @State private var showAddCustomGoal = false
    @State private var newGoalName = ""
    @State private var newGoalEmoji = "⭐"
    @AppStorage(MainMenuTabPreferences.fitVisibleKey)      private var fitTabVisible      = true
    @AppStorage(MainMenuTabPreferences.goalVisibleKey)     private var goalTabVisible     = true
    @AppStorage(MainMenuTabPreferences.mindVisibleKey)     private var mindTabVisible     = false
    @AppStorage(MainMenuTabPreferences.foodVisibleKey)     private var foodTabVisible     = false
    @AppStorage(MainMenuTabPreferences.tomoVisibleKey)     private var tomoTabVisible     = false
    @AppStorage(MainMenuTabPreferences.goalingoVisibleKey) private var goalingoTabVisible = false
    @AppStorage(MainMenuTabPreferences.logVisibleKey)      private var logTabVisible      = true
    @AppStorage(MainMenuTabPreferences.defaultTabKey) private var defaultTabRaw = MainMenuTab.fit.rawValue
    @AppStorage("simpleMode.enabled") private var simpleModeEnabled = false
    @AppStorage("simpleMode.installedAt") private var simpleModeInstalledAt = 0.0
    @State private var showNinetySecondPreview = false
    @AppStorage(MainMenuTabPreferences.orderKey) private var tabOrderRaw = MainMenuTabPreferences.storedOrder(from: MainMenuTabPreferences.defaultOrder)
    // 毎日の設定
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()
    // 毎日のカスタム項目
    @State private var showAddDailyCustom = false
    @State private var newDailyGoalName = ""
    @State private var newDailyGoalEmoji = "⭐"
    // 曜日毎の目標
    @State private var weekdayGoals: [WeekdayGoal] = (1...7).map { WeekdayGoal(weekday: $0) }
    @State private var selectedWeekday: Int? = nil
    @State private var showAddWeekdayCustom = false
    @State private var newWeekdayGoalName = ""
    @State private var newWeekdayGoalEmoji = "⭐"
    @State private var weekdayGoalsExpanded = false
    // SNSアカウント
    @AppStorage("sns.x.handle")        private var xHandle    = ""
    @AppStorage("sns.instagram.handle") private var igHandle  = ""
    @AppStorage("sns.facebook.url")    private var fbUrl      = ""
    @AppStorage("sns.line.id")         private var lineId     = ""
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.colorScheme") private var colorSchemePref = "light"

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    premiumSection
                    permissionBanner
                    dailyHabitsSection
                    motionSensitivitySection
                    intakeSection
                    habitStackSection
                    advancedSettingsSection
                    saveButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }

            closeSettingsFloatingButton
        }
        .navigationBarHidden(true)
        .task {
            await refreshPermStatus()
            setConfiguration = await AuthenticationManager.shared.getSetConfiguration()
            motionSensitivity = await AuthenticationManager.shared.getAllMotionSensitivity()
            await timeSlotManager.loadTodaySettings()
            await timeSlotManager.loadTodayProgress()
            loadDailyFixedGoals()
            loadWeekdayGoals()
        }
        .sheet(isPresented: $showPlusView) { PlusView() }
        .sheet(isPresented: $showHabitStack) { NavigationView { HabitStackView() } }
        .sheet(isPresented: $showHabitSettings) { habitSettingsSheet }
        .sheet(isPresented: $showRaceGoalSettings) { NavigationView { RaceGoalSettingsView() } }
        .sheet(isPresented: $showTimeSlotGoals) { NavigationView { TimeSlotGoalsView() } }
        .sheet(isPresented: $showShortcutsGuide) { ShortcutsGuideView() }
        .sheet(isPresented: $showAdvancedSettings) { advancedSettingsSheet }
        .sheet(isPresented: $showSensitivityEditor) {
            MotionSensitivityEditorView(configuration: $setConfiguration, sensitivity: $motionSensitivity)
        }
        .sheet(isPresented: $showIntakeSettings) {
            IntakeSettingsView()
        }
        .sheet(isPresented: $showDietGoalSettings) {
            NavigationView { DietGoalSettingsView() }
        }
        .sheet(isPresented: $showLLMSettings) {
            NavigationView { LLMSettingsView() }
        }
        .sheet(isPresented: $showAddCustomGoal) {
            addCustomGoalSheet
        }
        .sheet(isPresented: $showAddDailyCustom) {
            addDailyCustomGoalSheet
        }
        .sheet(isPresented: $showAddWeekdayCustom) {
            addWeekdayCustomGoalSheet
        }
        .fullScreenCover(isPresented: $showNinetySecondPreview) {
            ninetySecondPreviewSheet
        }
    }

    // MARK: - 90秒モードのプレビュー

    // モードを切り替えずに NinetySecondModeView の実画面を確認する。
    // メインボタンは無効（記録画面は開かない）で、✕ か「すべての機能を見る」で閉じる。
    private var ninetySecondPreviewSheet: some View {
        ZStack(alignment: .top) {
            NinetySecondModeView(
                installedAt: Date(timeIntervalSince1970: simpleModeInstalledAt > 0
                                  ? simpleModeInstalledAt
                                  : Date().timeIntervalSince1970),
                onStart: {},
                onExit: { showNinetySecondPreview = false },
                isPreview: true
            )
            .environmentObject(AuthenticationManager.shared)
            .environmentObject(timeSlotManager)

            HStack(spacing: 8) {
                Text("👀 プレビュー中 — ボタン操作は無効")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                Spacer()
                Button {
                    showNinetySecondPreview = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.14), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Header

    private var closeSettingsFloatingButton: some View {
        Button {
            saveAndClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoGreen)
                .frame(width: 40, height: 40)
                .background(Color(.systemBackground))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.14), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func closeSettings() {
        if let tab = MainMenuTab(rawValue: defaultTabRaw), tabVisible(tab) {
            selectedTab = tab.rawValue
        } else {
            selectedTab = enabledConfigurableTabs.first?.rawValue ?? MainMenuTab.fit.rawValue
        }
    }

    private func saveAndClose(showBanner: Bool = false) {
        notif.savePrefs()
        iOSWatchBridge.isWatchAutoLaunchEnabled = watchAutoLaunch
        Task {
            await AuthenticationManager.shared.saveSetConfiguration(setConfiguration)
            for (_, sensitivity) in motionSensitivity {
                await AuthenticationManager.shared.saveMotionSensitivity(sensitivity)
            }
            await MainActor.run {
                if permStatus == .authorized { notif.scheduleAllDaily() }
                if showBanner {
                    withAnimation { savedBanner = true }
                }
                closeSettings()
            }
        }
    }

    // MARK: - メニューのカスタマイズ

    private var orderedConfigurableTabs: [MainMenuTab] {
        MainMenuTabPreferences.orderedTabs(from: tabOrderRaw)
    }

    private var enabledConfigurableTabs: [MainMenuTab] {
        let enabled = orderedConfigurableTabs.filter { tabVisible($0) }
        return enabled.isEmpty ? [.fit] : enabled
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "paintbrush.fill",
                          title: "テーマ",
                          subtitle: "アプリ全体のカラーテーマを選択。デフォルトはライト（白ベース）。")

            Picker("テーマ", selection: $colorSchemePref) {
                Text("ライト").tag("light")
                Text("ダーク").tag("dark")
            }
            .pickerStyle(.segmented)
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private var tabMenuSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "rectangle.grid.1x2.fill",
                          title: "メニューのカスタマイズ",
                          subtitle: "タブを非表示にすると関連する情報も非表示。並び順を一番上にするとデフォルト表示")

            // 90秒モード（1画面に絞ったシンプル表示）
            VStack(spacing: 0) {
                Toggle(isOn: $simpleModeEnabled) {
                    HStack(spacing: 8) {
                        Text("⏱️").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("90秒モード")
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                            Text("「今日の90秒」だけの1画面表示に切り替え")
                                .font(.caption2).foregroundColor(Color.duoSubtitle)
                        }
                    }
                }
                .tint(Color.duoGreen)
                .padding(12)

                Divider().padding(.leading, 52)

                // モードを切り替えずに画面だけ確認できるプレビュー
                Button {
                    showNinetySecondPreview = true
                } label: {
                    HStack(spacing: 8) {
                        Text("👀").font(.title3)
                        Text("90秒モードの画面をプレビュー")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoGreen)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)


            VStack(spacing: 0) {
                ForEach(Array(orderedConfigurableTabs.enumerated()), id: \.element.id) { index, tab in
                    tabVisibilityRow(tab: tab, index: index)
                    if index < orderedConfigurableTabs.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func defaultTabOption(_ tab: MainMenuTab) -> some View {
        let isSelected = defaultTabBinding.wrappedValue == tab.rawValue
        return Button {
            defaultTabRaw = tab.rawValue
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17 * UIScale.font, weight: .black))
                Text(tab.label)
                    .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : Color.duoGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.duoGreen : Color.duoGreen.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.duoGreen : Color.duoGreen.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var goalTabSettingsButton: some View {
        Button {
            showDietGoalSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 14 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.duoGreen)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("GOAL目標設定")
                        .font(.system(size: 12 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("体重・体脂肪・カロリー目標")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(10)
            .background(Color.duoGreen.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var logTabVisibilityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoGreen)
                .frame(width: 32, height: 32)
                .background(Color.duoGreen.opacity(0.10))
                .clipShape(Circle())

            Text("LOGタブ")
                .font(.system(size: 13 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoDark)

            Spacer()
        }
        .padding(12)
    }

    private var defaultTabBinding: Binding<Int> {
        Binding(
            get: {
                if let tab = MainMenuTab(rawValue: defaultTabRaw), tabVisible(tab) {
                    return tab.rawValue
                }
                return enabledConfigurableTabs.first?.rawValue ?? MainMenuTab.fit.rawValue
            },
            set: { defaultTabRaw = $0 }
        )
    }

    private func tabVisibilityRow(tab: MainMenuTab, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.icon)
                .font(.system(size: 15 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoGreen)
                .frame(width: 32, height: 32)
                .background(Color.duoGreen.opacity(0.10))
                .clipShape(Circle())

            Text(tab.settingsLabel)
                .font(.system(size: 13 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoDark)

            Spacer()

            // 並び替えボタン・アクションボタン・トグル（右寄せ）
            HStack(spacing: 2) {
                Button {
                    moveTab(tab, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(index == 0 ? Color.gray.opacity(0.30) : Color.duoGreen)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button {
                    moveTab(tab, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(index == orderedConfigurableTabs.count - 1 ? Color.gray.opacity(0.30) : Color.duoGreen)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(index == orderedConfigurableTabs.count - 1)
            }

            // アクションボタン + トグル
            // ROUTINタブは固定表示のみ（設定ボタンだけ）、それ以外は全てトグルも表示
            if tab == .fit {
                // ROUTINタブ：常時表示・トグルなし
                Button {
                    showHabitSettings = true
                } label: {
                    Text("習慣設定")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.duoGreen.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                // その他タブ：トグル（表示/非表示）＋ 設定ボタン（該当タブのみ）
                HStack(spacing: 8) {
                    // 設定ボタン（対応するタブのみ）
                    switch tab {
                    case .goal:
                        Button { showDietGoalSettings = true } label: {
                            Text("目標設定")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoGreen)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    case .goalingo:
                        Button { showRaceGoalSettings = true } label: {
                            Text("ゴール設定")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoGreen)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    case .food:
                        Button { showIntakeSettings = true } label: {
                            Text("食事設定")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoOrange)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.duoOrange.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    default:
                        EmptyView()
                    }

                    Toggle("", isOn: tabVisibleBinding(tab))
                        .labelsHidden()
                        .tint(Color.duoGreen)
                }
            }
        }
        .padding(12)
    }

    private func tabVisible(_ tab: MainMenuTab) -> Bool {
        switch tab {
        case .fit:      return true               // ROUTINタブは常に表示
        case .goal:     return goalTabVisible
        case .mind:     return mindTabVisible
        case .food:     return foodTabVisible
        case .tomo:     return tomoTabVisible
        case .goalingo: return goalingoTabVisible
        }
    }

    private func tabVisibleBinding(_ tab: MainMenuTab) -> Binding<Bool> {
        Binding(
            get: { tabVisible(tab) },
            set: { newValue in
                setTabVisible(tab, newValue)
            }
        )
    }

    private func setTabVisible(_ tab: MainMenuTab, _ newValue: Bool) {
        if tab == .fit { return }  // ROUTINタブは常に表示（変更不可）
        let currentlyEnabledCount = MainMenuTab.allCases.filter { tabVisible($0) }.count
        if !newValue && currentlyEnabledCount <= 1 {
            return
        }

        switch tab {
        case .fit:      break
        case .goal:     goalTabVisible     = newValue
        case .mind:     mindTabVisible     = newValue
        case .food:     foodTabVisible     = newValue
        case .tomo:     tomoTabVisible     = newValue
        case .goalingo: goalingoTabVisible = newValue
        }

        UserDefaults.standard.set(newValue, forKey: MainMenuTabPreferences.visibleKey(for: tab))

        let enabledTabs = orderedConfigurableTabs.filter { currentTab in
            currentTab == tab ? newValue : tabVisible(currentTab)
        }
        if let defaultTab = MainMenuTab(rawValue: defaultTabRaw),
           !enabledTabs.contains(defaultTab) {
            defaultTabRaw = enabledTabs.first?.rawValue ?? MainMenuTab.fit.rawValue
        }
    }

    private func moveTab(_ tab: MainMenuTab, direction: Int) {
        var tabs = orderedConfigurableTabs
        guard let currentIndex = tabs.firstIndex(of: tab) else { return }
        let newIndex = currentIndex + direction
        guard tabs.indices.contains(newIndex) else { return }
        tabs.swapAt(currentIndex, newIndex)
        tabOrderRaw = MainMenuTabPreferences.storedOrder(from: tabs)
        // 先頭タブを自動的にデフォルトに設定
        defaultTabRaw = tabs.first?.rawValue ?? MainMenuTab.fit.rawValue
    }

    // MARK: - Plus セクション

    private var premiumSection: some View {
        Button { showPlusView = true } label: {
            HStack(spacing: 12) {
                PlusBadge(size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Fitingo Plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "#FF8C00"))
                        if plus.isPlus {
                            Text("有効")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#FF8C00"))
                                .cornerRadius(6)
                        }
                    }
                    Text(plus.isPlus
                         ? (plus.isAdmin ? "Admin" : plus.codeUnlocked ? "コード解放済み" : "サブスク有効")
                         : "全機能を解放 · 月額¥480〜")
                        .font(.system(size: 11))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(plus.isPlus
                        ? Color(hex: "#FFD700").opacity(0.5) : Color(.systemGray5), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 毎日の習慣・目標設定（インライン）

    private var dailyHabitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "calendar.badge.clock",
                          title: "毎日の習慣・目標設定",
                          subtitle: "1日全体・曜日別・時間帯の目標を一括管理")

            if timeSlotManager.isLoading {
                ProgressView()
                    .tint(Color.duoGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                // 毎日の設定
                dailyFixedGoalsSection

                // 時間帯別設定ボタン
                Button { showTimeSlotGoals = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 15 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                            .frame(width: 32, height: 32)
                            .background(Color.duoGreen.opacity(0.10))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("時間帯別の目標")
                                .font(.system(size: 15 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoDark)
                            Text("朝・昼・午後・夜の時間帯ごとに設定")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(.plain)

                // 曜日毎の目標
                weekdayGoalsSection

                // ゴール目標設定ボタン（レース・トライアスロン等）
                Button { showRaceGoalSettings = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 15 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoOrange)
                            .frame(width: 32, height: 32)
                            .background(Color.duoOrange.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ゴール目標設定")
                                .font(.system(size: 13 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoDark)
                            Text("大会・レース目標を設定（スイム・バイク・ラン）")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 毎日の設定（インライン）

    private var dailyFixedGoalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("📆").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("毎日の設定")
                        .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("曜日に関わらず毎日Apple Healthから自動チェック")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }
            .padding(.bottom, 14)

            Toggle(isOn: Binding(
                get: { dailyFixedGoals.foodEnabled },
                set: { v in dailyFixedGoals.foodEnabled = v; foodTabVisible = v; saveDailyFixedGoals() }
            )) {
                HStack(spacing: 8) {
                    Text("🍽️").font(.title3)
                    Text("食事の記録")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                }
            }.tint(Color.duoGreen)

            if dailyFixedGoals.foodEnabled {
                HStack(spacing: 8) {
                    Text("摂取カロリー目標")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                    Spacer(minLength: 4)
                    Stepper(
                        value: Binding(
                            get: { dietGoalManager.settings.dailyIntakeGoal },
                            set: { v in
                                dietGoalManager.settings.dailyIntakeGoal = v
                                TimeSlotManager.shared.syncMealGoalFromDietGoal()
                            }
                        ),
                        in: 800...5000, step: 50
                    ) {
                        Text("\(dietGoalManager.settings.dailyIntakeGoal) kcal")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoOrange)
                            .lineLimit(1)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)

                Divider().padding(.vertical, 4)

                HStack(spacing: 8) {
                    Text("水分量目標")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                    Spacer(minLength: 4)
                    Stepper(
                        value: Binding(
                            get: { timeSlotManager.settings.globalGoals.dailyDrinkMl },
                            set: { v in
                                timeSlotManager.settings.globalGoals.dailyDrinkMl = v
                                timeSlotManager.applyGlobalMealDrinkToSlots()
                                timeSlotManager.saveGoalTemplate()
                                Task {
                                    await timeSlotManager.saveTodaySettings()
                                    // 水分目標の単一ソースである IntakeSettings（1日のゴール・
                                    // ダッシュボード・Watch連携で参照）にも反映する
                                    var intake = await AuthenticationManager.shared.getIntakeSettings()
                                    intake.dailyWaterGoal = v
                                    await AuthenticationManager.shared.saveIntakeSettings(intake)
                                }
                            }
                        ),
                        in: 500...5000, step: 100
                    ) {
                        Text("\(timeSlotManager.settings.globalGoals.dailyDrinkMl) ml")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color(hex: "#1CB0F6"))
                            .lineLimit(1)
                            .frame(minWidth: 72, maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider().padding(.vertical, 10)

            Toggle(isOn: Binding(
                get: { dailyFixedGoals.weightEnabled },
                set: { v in dailyFixedGoals.weightEnabled = v; saveDailyFixedGoals() }
            )) {
                HStack(spacing: 8) {
                    Text("⚖️").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("体重を計測")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                        Text("1日に1回以上の計測の登録で自動判定")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                }
            }.tint(Color.duoGreen)

            Divider().padding(.vertical, 10)

            Toggle(isOn: Binding(
                get: { dailyFixedGoals.sleepEnabled },
                set: { v in dailyFixedGoals.sleepEnabled = v; saveDailyFixedGoals() }
            )) {
                HStack(spacing: 8) {
                    Text("😴").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("睡眠の計測")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                        Text("前夜の睡眠データ登録で自動判定")
                            .font(.caption2).foregroundColor(Color.duoSubtitle)
                    }
                }
            }.tint(Color.duoGreen)

            if dailyFixedGoals.sleepEnabled {
                Divider().padding(.vertical, 6)
                HStack {
                    Text("目標睡眠時間")
                        .font(.subheadline)
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Stepper(
                        "\(dailyFixedGoals.sleepHoursGoal)時間",
                        value: Binding(
                            get: { dailyFixedGoals.sleepHoursGoal },
                            set: { v in dailyFixedGoals.sleepHoursGoal = v; saveDailyFixedGoals() }
                        ),
                        in: 4...12
                    )
                    .fixedSize()
                }
                .padding(.leading, 36)
            }

            Divider().padding(.vertical, 10)

            // カスタム項目（スクショ完了）
            HStack(spacing: 8) {
                Text("📱").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("カスタム項目")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                    Text("スクリーンショットをアップロードすると完了")
                        .font(.caption2).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Button {
                    showAddDailyCustom = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                }
            }

            ForEach(dailyFixedGoals.customGoals) { cg in
                HStack(spacing: 8) {
                    Text(cg.emoji).font(.subheadline)
                    Text(cg.name)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Button {
                        dailyFixedGoals.customGoals.removeAll { $0.id == cg.id }
                        saveDailyFixedGoals()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(Color.duoRed.opacity(0.7))
                            .font(.subheadline)
                    }
                }
                .padding(.leading, 36)
            }

            if dailyFixedGoals.customGoals.isEmpty {
                Text("例: Duolingo📱・読書📖・勉強📚・日記📓など")
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.leading, 36)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 習慣設定シート

    private var habitSettingsSheet: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    dailyFixedGoalsSection
                    weekdayGoalsSection

                    NavigationLink {
                        TimeSlotGoalsView()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 15 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGreen)
                                .frame(width: 32, height: 32)
                                .background(Color.duoGreen.opacity(0.10))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("時間帯別の目標")
                                    .font(.system(size: 13 * UIScale.font, weight: .black))
                                    .foregroundColor(Color.duoDark)
                                Text("朝・昼・午後・夜の時間帯ごとに設定")
                                    .font(.caption)
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        .padding(14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("習慣設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { showHabitSettings = false }
                        .foregroundColor(Color.duoGreen).fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - 毎日の設定 永続化

    private func loadDailyFixedGoals() {
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let saved = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            dailyFixedGoals = saved
        }
        // FOODタブの表示は「毎日の設定 > 食事の記録」に追従させる
        foodTabVisible = dailyFixedGoals.foodEnabled
    }

    private func saveDailyFixedGoals() {
        if let data = try? JSONEncoder().encode(dailyFixedGoals) {
            UserDefaults.standard.set(data, forKey: "dailyFixedGoals_v1")
        }
    }

    // MARK: - 曜日毎の目標（一覧形式）

    private var weekdayGoalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { weekdayGoalsExpanded.toggle() }
            } label: {
                HStack {
                    Text("📅").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("曜日毎の目標")
                            .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                        Text("曜日ごとに運動・勉強などの目標を設定")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                        .rotationEffect(.degrees(weekdayGoalsExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if weekdayGoalsExpanded {
                VStack(spacing: 0) {
                    ForEach(weekdayGoals.indices, id: \.self) { idx in
                        weekdayRowView(idx: idx)
                        if idx < weekdayGoals.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func weekdayRowView(idx: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(weekdayGoals[idx].label)
                .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(weekdayGoals[idx].hasAnyGoal ? Color.duoGreen : Color.duoSubtitle)
                .frame(width: 24, alignment: .center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    weekdayToggleChip("🏃", "活動", weekdayGoals[idx].exerciseEnabled) {
                        weekdayGoals[idx].exerciseEnabled.toggle(); saveWeekdayGoals()
                    }
                    weekdayToggleChip("📚", "勉強", weekdayGoals[idx].studyEnabled) {
                        weekdayGoals[idx].studyEnabled.toggle(); saveWeekdayGoals()
                    }
                    weekdayToggleChip("🚫", "禁酒", weekdayGoals[idx].noAlcoholEnabled) {
                        weekdayGoals[idx].noAlcoholEnabled.toggle(); saveWeekdayGoals()
                    }
                    ForEach(weekdayGoals[idx].customGoals) { cg in
                        weekdayCustomChip(cg.emoji, cg.name) {
                            weekdayGoals[idx].customGoals.removeAll { $0.id == cg.id }
                            saveWeekdayGoals()
                        }
                    }
                    Button {
                        selectedWeekday = weekdayGoals[idx].weekday
                        showAddWeekdayCustom = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color(.systemGray6))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func weekdayToggleChip(_ emoji: String, _ label: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(emoji).font(.system(size: 11 * UIScale.font))
                Text(label)
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(isOn ? .white : Color.duoSubtitle)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isOn ? Color.duoGreen : Color(.systemGray6))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    private func weekdayCustomChip(_ emoji: String, _ label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(emoji).font(.system(size: 11 * UIScale.font))
            Text(label)
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(hex: "#1CB0F6"))
        .cornerRadius(7)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private var addDailyCustomGoalSheet: some View {
        let presets: [DailyCustomGoal] = [
            DailyCustomGoal(name: "Duolingo",  emoji: "🦉"),
            DailyCustomGoal(name: "読書",       emoji: "📖"),
            DailyCustomGoal(name: "勉強",       emoji: "📚"),
            DailyCustomGoal(name: "日記",       emoji: "📓"),
            DailyCustomGoal(name: "瞑想",       emoji: "🧘"),
            DailyCustomGoal(name: "ジョギング", emoji: "🏃"),
        ]
        return NavigationView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    TextField("絵文字", text: $newDailyGoalEmoji)
                        .font(.system(size: 28 * UIScale.font))
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    TextField("項目名（例: Duolingo、読書…）", text: $newDailyGoalName)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            newDailyGoalEmoji = preset.emoji
                            newDailyGoalName  = preset.name
                        } label: {
                            VStack(spacing: 4) {
                                Text(preset.emoji).font(.title2)
                                Text(preset.name).font(.caption2).fontWeight(.bold).foregroundColor(Color.duoDark)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(newDailyGoalName == preset.name ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("カスタム項目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        newDailyGoalName = ""; newDailyGoalEmoji = "⭐"; showAddDailyCustom = false
                    }.foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard !newDailyGoalName.isEmpty else { return }
                        let goal = DailyCustomGoal(
                            name: newDailyGoalName,
                            emoji: newDailyGoalEmoji.isEmpty ? "⭐" : String(newDailyGoalEmoji.prefix(2))
                        )
                        dailyFixedGoals.customGoals.append(goal)
                        saveDailyFixedGoals()
                        newDailyGoalName = ""; newDailyGoalEmoji = "⭐"; showAddDailyCustom = false
                    }
                    .foregroundColor(Color.duoGreen).fontWeight(.bold)
                    .disabled(newDailyGoalName.isEmpty)
                }
            }
        }
    }

    private var addWeekdayCustomGoalSheet: some View {
        let presets: [WeekdayCustomGoal] = [
            WeekdayCustomGoal(name: "読書",     emoji: "📖"),
            WeekdayCustomGoal(name: "英語学習", emoji: "🌎"),
            WeekdayCustomGoal(name: "ジョギング", emoji: "🏃"),
            WeekdayCustomGoal(name: "日記",     emoji: "📓"),
            WeekdayCustomGoal(name: "禁酒",     emoji: "🚫"),
            WeekdayCustomGoal(name: "瞑想",     emoji: "🧘"),
        ]
        return NavigationView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    TextField("絵文字", text: $newWeekdayGoalEmoji)
                        .font(.system(size: 28 * UIScale.font))
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    TextField("項目名（例: 読書、ジョギング…）", text: $newWeekdayGoalName)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            newWeekdayGoalEmoji = preset.emoji
                            newWeekdayGoalName  = preset.name
                        } label: {
                            VStack(spacing: 4) {
                                Text(preset.emoji).font(.title2)
                                Text(preset.name).font(.caption2).fontWeight(.bold).foregroundColor(Color.duoDark)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(newWeekdayGoalName == preset.name ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("カスタム目標を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        newWeekdayGoalName = ""; newWeekdayGoalEmoji = "⭐"; showAddWeekdayCustom = false
                    }.foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard let weekday = selectedWeekday,
                              let idx = weekdayGoals.firstIndex(where: { $0.weekday == weekday }),
                              !newWeekdayGoalName.isEmpty else { return }
                        let goal = WeekdayCustomGoal(
                            name: newWeekdayGoalName,
                            emoji: newWeekdayGoalEmoji.isEmpty ? "⭐" : String(newWeekdayGoalEmoji.prefix(2))
                        )
                        weekdayGoals[idx].customGoals.append(goal)
                        saveWeekdayGoals()
                        newWeekdayGoalName = ""; newWeekdayGoalEmoji = "⭐"; showAddWeekdayCustom = false
                    }
                    .foregroundColor(Color.duoGreen).fontWeight(.bold)
                    .disabled(newWeekdayGoalName.isEmpty)
                }
            }
        }
    }

    // MARK: - 曜日毎の目標 永続化

    private func loadWeekdayGoals() {
        if let data = UserDefaults.standard.data(forKey: "weekdayGoals_v1"),
           let saved = try? JSONDecoder().decode([WeekdayGoal].self, from: data) {
            weekdayGoals = saved
        }
    }

    private func saveWeekdayGoals() {
        if let data = try? JSONEncoder().encode(weekdayGoals) {
            UserDefaults.standard.set(data, forKey: "weekdayGoals_v1")
        }
    }

    private func smallDefaultButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9 * UIScale.font, weight: .black))
                Text("初期値")
                    .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
            }
            .foregroundColor(Color.duoSubtitle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func resetTimeSlotGoalsToDefault() {
        let globalGoals = timeSlotManager.settings.globalGoals
        timeSlotManager.settings = DailyTimeSlotSettings(date: timeSlotManager.settings.date)
        timeSlotManager.settings.globalGoals = globalGoals
        timeSlotManager.applyGlobalMealDrinkToSlots()
        Task { await timeSlotManager.saveTodaySettings() }
    }

    private var globalDivider: some View {
        Divider().padding(.vertical, 10)
    }

    private func globalToggleRow(emoji: String, label: String, badge: String?, badgeColor: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Text(emoji).font(.title3)
                    .opacity(isOn.wrappedValue ? 1.0 : 0.35)
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(isOn.wrappedValue ? Color.duoDark : Color(.systemGray3))
                if let badge, isOn.wrappedValue {
                    Text(badge)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }.tint(Color.duoGreen)
    }

    private func globalStepperRow(label: String, valueText: String, color: Color, value: Binding<Int>, in range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption).foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(valueText)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .cornerRadius(6)
            settingsStepperControls(value: value, range: range, step: step, color: color)
        }
        .padding(.leading, 40)
        .padding(.bottom, 4)
    }

    // MARK: - 時間帯別カード（インライン）

    private func slotReminderID(for slot: TimeSlot) -> String {
        switch slot {
        case .midnight, .morning: return NotificationManager.ID.amReminder
        case .noon:               return NotificationManager.ID.noonReminder
        case .afternoon:          return NotificationManager.ID.afternoonReminder
        case .evening:            return NotificationManager.ID.pmReminder
        }
    }

    private func slotStepperRow(emoji: String, label: String, valueText: String, valueColor: Color, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 8) {
            Text(emoji).font(.title3)
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(Color.duoDark)
            Spacer()
            Text(valueText)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(valueColor)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(valueColor.opacity(0.12))
                .cornerRadius(7)
            settingsStepperControls(value: value, range: range, step: step, color: valueColor)
        }
    }

    private func settingsStepperControls(value: Binding<Int>, range: ClosedRange<Int>, step: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            settingsStepperButton(
                systemName: "minus",
                isEnabled: value.wrappedValue > range.lowerBound,
                color: color
            ) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }

            settingsStepperButton(
                systemName: "plus",
                isEnabled: value.wrappedValue < range.upperBound,
                color: color
            ) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
        }
        .padding(2)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.16), lineWidth: 0.8)
        )
    }

    private func settingsStepperButton(systemName: String, isEnabled: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12 * UIScale.font, weight: .black))
                .foregroundColor(isEnabled ? color : Color(.systemGray2))
                .frame(width: 25, height: 25)
                .background(isEnabled ? Color.white.opacity(0.92) : Color(.systemGray6))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isEnabled ? color.opacity(0.22) : Color(.systemGray4).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: color.opacity(isEnabled ? 0.10 : 0.0), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - カスタム目標追加シート

    private var addCustomGoalSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("絵文字").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                    TextField("絵文字を入力（例: 📚）", text: $newGoalEmoji)
                        .font(.system(size: 36 * UIScale.font)).multilineTextAlignment(.center)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("目標名").font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                    TextField("例: 読書、Duolingo、禁酒…", text: $newGoalName)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(CustomDailyGoal.presets) { preset in
                        Button {
                            newGoalEmoji = preset.emoji; newGoalName = preset.name
                        } label: {
                            VStack(spacing: 4) {
                                Text(preset.emoji).font(.title2)
                                Text(preset.name).font(.caption2).fontWeight(.bold).foregroundColor(Color.duoDark)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(newGoalName == preset.name ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(10)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("カスタム目標を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { newGoalName = ""; newGoalEmoji = "⭐"; showAddCustomGoal = false }
                        .foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        guard !newGoalName.isEmpty else { return }
                        let goal = CustomDailyGoal(name: newGoalName, emoji: newGoalEmoji.isEmpty ? "⭐" : String(newGoalEmoji.prefix(2)))
                        timeSlotManager.settings.globalGoals.customGoals.append(goal)
                        Task { await timeSlotManager.saveTodaySettings() }
                        newGoalName = ""; newGoalEmoji = "⭐"; showAddCustomGoal = false
                    }
                    .foregroundColor(Color.duoGreen).fontWeight(.bold).disabled(newGoalName.isEmpty)
                }
            }
        }
    }


    // MARK: - ダイエット目標設定

    private var dietGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "🎯", title: "ダイエット目標",
                          subtitle: "目標体重・カロリー収支ゴール")

            Button {
                showDietGoalSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("目標設定")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        let s = DietGoalManager.shared.settings
                        let deficit = s.dailyDeficitGoal
                        if s.targetWeight > 0 {
                            Text(String(format: "目標 %.1f kg  |  1日収支 %+d kcal", s.targetWeight, deficit))
                                .font(.caption).foregroundColor(Color.duoSubtitle)
                        } else {
                            Text("目標体重・カロリーゴールを設定")
                                .font(.caption).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 摂取記録設定

    private var intakeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "fork.knife", title: "摂取記録",
                          subtitle: "食事・水分・コーヒー・アルコール")

            Button {
                showIntakeSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(Color.duoOrange)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("デフォルト設定")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("カロリー量やアルコール種類など")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - トレーニング・メニュー、モーション設定

    private var motionSensitivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "sensor.fill", title: "トレーニング・メニュー、モーション設定",
                          subtitle: "種目・回数・検出精度をまとめて調整")

            Button {
                showSensitivityEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sensor.fill")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("メニュー・感度を編集")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("\(setConfiguration.exercises.count)種目 登録済み · iPhone・Apple Watch共通")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 通知権限バナー

    private var permissionBanner: some View {
        Group {
            switch permStatus {
            case .denied:
                HStack(spacing: 10) {
                    Text("🚫").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("通知がブロックされています")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color(hex: "#7f0000"))
                        Text("設定アプリ → Fitingo → 通知 から許可してください")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#7f0000"))
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("設定へ")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(Color(hex: "#FCE4EC"))
                .cornerRadius(14)

            case .notDetermined:
                Button {
                    Task {
                        await notif.requestPermission()
                        await refreshPermStatus()
                        if permStatus == .authorized { notif.scheduleAllDaily() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                        Text("通知を有効にする")
                            .fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.duoGreen)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

            default:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen)
                    Text("通知が有効です")
                        .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoGreen)
                    Spacer()
                    Button {
                        notif.scheduleAllDaily()
                        notif.savePrefs()
                    } label: {
                        Text("テスト再スケジュール")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(12)
                .background(Color(hex: "#D7FFB8"))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - LLMセクション

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "brain.head.profile", title: "AI設定",
                          subtitle: "クォータ・APIキー管理")

            // ─ 詳細設定（既存）
            Button { showLLMSettings = true } label: {
                HStack(spacing: 12) {
                    Text("🤖").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("フォトログAI詳細設定")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("モデル・プロバイダー選択（上級者向け）")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            // ─ カスタム API キー
            Button { showAPIKeySheet = true } label: {
                HStack(spacing: 12) {
                    Text("🔑").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自分のAPIキーを登録")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        if AIQuotaManager.shared.hasCustomKey {
                            Label("登録済み（無制限利用）", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Text("登録でAI利用が無制限に（自己負担）")
                                .font(.caption).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            // ─ クォータ説明
            VStack(alignment: .leading, spacing: 4) {
                Text("AI利用上限")
                    .font(.caption).fontWeight(.bold).foregroundColor(Color.duoSubtitle)
                Text("• 5日チャレンジ中: 全カテゴリ合計 1回/日")
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                Text("• 無料: 1回/日・カテゴリ（食事AI・語学AI）")
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                Text("• Plus: 3回/日・カテゴリ")
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                Text("• APIキー登録: 無制限（自己負担）")
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showAPIKeySheet) {
            CustomAPIKeySheet()
        }
    }

    // MARK: - 詳細設定

    private var advancedSettingsSection: some View {
        Button { showAdvancedSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 15 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(width: 32, height: 32)
                    .background(Color.duoSubtitle.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("詳細設定")
                        .font(.system(size: 15 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("テーマ・メニュー・AI・Apple Watch・連動アプリ・SNS")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var advancedSettingsSheet: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        appearanceSection
                        tabMenuSettingsSection
                        llmSection
                        watchSection
                        linkedAppsSection
                        snsAccountSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("詳細設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { showAdvancedSettings = false }
                        .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Apple Watch セクション

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "applewatch", title: "Apple Watch",
                          subtitle: "Watch連携の動作設定")

            VStack(spacing: 0) {
                // 自動起動トグル
                HStack(spacing: 12) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自動ワークアウト起動")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("iOSアプリを開いたとき、Watchのワークアウトを自動開始")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: $watchAutoLaunch)
                        .tint(Color.duoGreen)
                        .labelsHidden()
                }
                .padding(14)

                // 説明バナー
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                    Text("Watch側のアプリが起動済みのとき、iOSアプリを開くと同時にワークアウト画面へ自動遷移します")
                        .font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - ハビットスタックセクション

    private var habitStackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "link.circle.fill", title: "ハビットスタック",
                          subtitle: "既存の日課とトレーニングをセット")

            Button { showHabitStack = true } label: {
                HStack(spacing: 12) {
                    Text("🔗").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ハビットスタックを管理")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("歯磨き・シャワーなどの日課の後に通知")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - SNSアカウント設定セクション

    private var snsAccountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "person.2.wave.2.fill", title: "SNSアカウント",
                          subtitle: "シェア時に自分のアカウントへ投稿")
            VStack(spacing: 0) {
                snsRow(emoji: "𝕏", label: "X (Twitter)",
                       placeholder: "@username",
                       text: $xHandle)
                Divider().padding(.leading, 54)
                snsRow(emoji: "📸", label: "Instagram",
                       placeholder: "@username",
                       text: $igHandle)
                Divider().padding(.leading, 54)
                snsRow(emoji: "🔵", label: "Facebook",
                       placeholder: "プロフィールURL or 名前",
                       text: $fbUrl)
                Divider().padding(.leading, 54)
                snsRow(emoji: "💬", label: "LINE",
                       placeholder: "LINE ID",
                       text: $lineId)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

            Text("登録したアカウントはシェアシートに表示され、タップで直接投稿できます。アカウント情報はこのデバイスにのみ保存されます。")
                .font(.caption2)
                .foregroundColor(Color.duoSubtitle)
                .padding(.horizontal, 4)
                .padding(.top, 6)
        }
    }

    private func snsRow(emoji: String, label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                TextField(placeholder, text: text)
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            if !text.wrappedValue.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.duoGreen)
                    .font(.system(size: 16))
            }
        }
        .padding(14)
    }

    // MARK: - 連動アプリセクション

    private var linkedAppsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "square.stack.3d.up.fill", title: "連動アプリ",
                          subtitle: "他のアプリを開いたときFitingoを起動")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("🦉").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOSショートカットで自動化")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("Duolingoなどを開いたとき、Fitingoも自動起動")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Button { showShortcutsGuide = true } label: {
                        Text("設定方法")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(14)
            }
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 保存ボタン

    private var saveButton: some View {
        Button {
            saveAndClose(showBanner: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: savedBanner ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                Text(savedBanner ? "保存しました！" : "設定を保存")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(savedBanner ? Color(hex: "#46A302") : Color.duoGreen)
            .cornerRadius(14)
            .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoDark)
                Text(subtitle)
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(.bottom, 8)
    }

    private func refreshPermStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permStatus = settings.authorizationStatus
    }
}


// MARK: - ShortcutsGuideView

private struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("iPhoneの「ショートカット」アプリを開く", "app.badge"),
        ("「オートメーション」タブ → 右上の「＋」", "plus.circle"),
        ("「App」を選択 → 連動させたいアプリ（例: Duolingo）を選ぶ", "app.connected.to.app.below.fill"),
        ("「開いたとき」を選択 → 「次へ」", "chevron.right.circle"),
        ("「アクションを追加」→「URLを開く」→ fitingo:// を入力", "link"),
        ("「完了」で保存", "checkmark.circle.fill"),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("iOSショートカットで\n他のアプリと連動させる方法")
                            .font(.title3).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.duoGreen)
                                        .frame(width: 28, height: 28)
                                    Text("\(idx + 1)")
                                        .font(.caption).fontWeight(.black).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.0)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(Color.duoDark)
                                    Image(systemName: step.1)
                                        .font(.caption)
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        Text("設定後はDuolingoを開くとFitingoが自動的に前面に出てきます")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("ショートカット設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
    }
}

// MARK: - MotionSensitivityEditorView（トレーニング・メニュー、モーション設定）

struct MotionSensitivityEditorView: View {
    @Binding var configuration: SetConfiguration
    @Binding var sensitivity: [String: MotionSensitivity]
    @Environment(\.dismiss) private var dismiss
    @State private var editingExercises: [ExerciseInSet]
    @State private var editingSensitivity: [String: MotionSensitivity]

    private let availableExercises = [("pushup","腕立て伏せ","💪"),("squat","スクワット","🏋️"),("situp","腹筋","🔥"),("lunge","ランジ","🦵"),("burpee","バーピー","⚡"),("plank","プランク","🧘")]

    init(configuration: Binding<SetConfiguration>, sensitivity: Binding<[String: MotionSensitivity]>) {
        self._configuration = configuration
        self._sensitivity = sensitivity
        self._editingExercises = State(initialValue: configuration.wrappedValue.exercises.sorted { $0.order < $1.order })
        self._editingSensitivity = State(initialValue: sensitivity.wrappedValue)
    }

    private func isIncluded(_ id: String) -> Bool { editingExercises.contains { $0.exerciseId == id } }

    private func includeBinding(id: String, name: String) -> Binding<Bool> {
        Binding(
            get: { isIncluded(id) },
            set: { newValue in
                if newValue {
                    guard !isIncluded(id) else { return }
                    editingExercises.append(ExerciseInSet(exerciseId: id, exerciseName: name, targetReps: 10, order: editingExercises.count))
                } else {
                    editingExercises.removeAll { $0.exerciseId == id }
                }
            }
        )
    }

    private func repsBinding(id: String) -> Binding<Int> {
        Binding(
            get: { editingExercises.first { $0.exerciseId == id }?.targetReps ?? 10 },
            set: { newValue in
                guard let idx = editingExercises.firstIndex(where: { $0.exerciseId == id }) else { return }
                editingExercises[idx].targetReps = newValue
            }
        )
    }

    private func sensitivityBinding(id: String) -> Binding<MotionSensitivity> {
        Binding(
            get: { editingSensitivity[id] ?? MotionSensitivity.defaultSettings[id]! },
            set: { editingSensitivity[id] = $0 }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill").font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                            Text("種目ごとに、1セットのメニューに含めるか・回数・モーション検出の感度を設定します。").font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                        }.padding(12).background(Color(hex: "#E5F8FF")).cornerRadius(12)

                        ForEach(availableExercises, id: \.0) { id, name, emoji in
                            TrainingMenuRowEditor(
                                exerciseName: "\(emoji) \(name)",
                                isIncluded: includeBinding(id: id, name: name),
                                targetReps: repsBinding(id: id),
                                sensitivity: sensitivityBinding(id: id)
                            )
                        }
                        Button { editingSensitivity = MotionSensitivity.defaultSettings } label: {
                            HStack(spacing: 8) { Image(systemName: "arrow.counterclockwise"); Text("感度をデフォルトに戻す").fontWeight(.bold) }
                                .foregroundColor(Color.duoSubtitle).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color(.systemBackground)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.duoSubtitle.opacity(0.3), lineWidth: 1))
                        }.buttonStyle(.plain)
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
                }
            }
            .navigationTitle("トレーニング・メニュー、モーション設定").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        var exercises = editingExercises
                        for i in exercises.indices { exercises[i].order = i }
                        configuration.exercises = exercises
                        sensitivity = editingSensitivity
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
        }
    }
}

struct TrainingMenuRowEditor: View {
    let exerciseName: String
    @Binding var isIncluded: Bool
    @Binding var targetReps: Int
    @Binding var sensitivity: MotionSensitivity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(exerciseName).font(.headline).fontWeight(.bold).foregroundColor(Color.duoDark)
                Spacer()
                Text("メニューに含める").font(.caption).foregroundColor(Color.duoSubtitle)
                Toggle("", isOn: $isIncluded).labelsHidden().tint(Color.duoGreen)
            }
            if isIncluded {
                HStack(spacing: 8) {
                    Text("回数").font(.subheadline).foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Button { if targetReps > 5 { targetReps -= 5 } } label: { Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(targetReps > 5 ? Color.duoGreen : Color.gray.opacity(0.3)) }.disabled(targetReps <= 5)
                    Text("\(targetReps)").font(.title3).fontWeight(.black).foregroundColor(Color.duoDark).frame(width: 40)
                    Button { if targetReps < 50 { targetReps += 5 } } label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(targetReps < 50 ? Color.duoGreen : Color.gray.opacity(0.3)) }.disabled(targetReps >= 50)
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("感度").font(.subheadline).foregroundColor(Color.duoSubtitle); Spacer(); Text(sensitivityLabel(sensitivity.threshold)).font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen) }
                HStack(spacing: 8) { Text("低").font(.caption2).foregroundColor(Color.duoSubtitle); Slider(value: $sensitivity.threshold, in: 0.02...0.20, step: 0.02).tint(Color.duoGreen); Text("高").font(.caption2).foregroundColor(Color.duoSubtitle) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("最小間隔").font(.subheadline).foregroundColor(Color.duoSubtitle); Spacer(); Text(String(format: "%.1f秒", sensitivity.minInterval)).font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen) }
                HStack(spacing: 8) { Text("短").font(.caption2).foregroundColor(Color.duoSubtitle); Slider(value: $sensitivity.minInterval, in: 0.3...2.0, step: 0.1).tint(Color.duoGreen); Text("長").font(.caption2).foregroundColor(Color.duoSubtitle) }
            }
        }.padding(14).background(Color(.systemBackground)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
    private func sensitivityLabel(_ threshold: Double) -> String {
        switch threshold { case 0...0.05: return "最高"; case 0.05...0.08: return "高"; case 0.08...0.12: return "中"; case 0.12...0.16: return "低"; default: return "最低" }
    }
}

// MARK: - カスタム API キー設定シート

struct CustomAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var quota = AIQuotaManager.shared
    @State private var keyInput: String = ""
    @State private var errorMsg: String? = nil
    @State private var saved = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API キーを登録すると、食事AI・語学AIが無制限で使えます（OpenAIへの料金はご自身の負担です）。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Link("APIキーを取得する →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } header: { Text("OpenAI APIキー") }

                Section {
                    SecureField("sk-...", text: $keyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    if let err = errorMsg {
                        Text(err).font(.caption).foregroundColor(.red)
                    }

                    if quota.hasCustomKey && keyInput.isEmpty {
                        HStack {
                            Label("現在登録済み", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.green)
                            Spacer()
                            Button("削除", role: .destructive) {
                                Task {
                                    try? await quota.clearCustomAPIKey()
                                    dismiss()
                                }
                            }
                            .font(.caption)
                        }
                    }
                } header: { Text("キーを入力") }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("利用制限のまとめ").font(.caption).fontWeight(.bold)
                        ForEach([
                            "5日チャレンジ中: 全カテゴリ合計 1回/日",
                            "無料: 食事AI・語学AI それぞれ 1回/日",
                            "Plus: 食事AI・語学AI それぞれ 3回/日",
                            "APIキー登録: 無制限（自己負担）",
                        ], id: \.self) { line in
                            Text("• \(line)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                } header: { Text("クォータ") }
            }
            .navigationTitle("AIキー設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard keyInput.hasPrefix("sk-") || keyInput.isEmpty else {
                            errorMsg = "OpenAI APIキーは sk- で始まります"
                            return
                        }
                        Task {
                            do {
                                try await quota.saveCustomAPIKey(keyInput)
                                dismiss()
                            } catch {
                                errorMsg = "保存に失敗しました: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(quota.isSavingKey)
                }
            }
        }
    }
}

#Preview {
    NavigationView { SettingsView(selectedTab: .constant(4)) }
}
