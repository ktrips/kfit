import SwiftUI

struct RaceGoalSettingsView: View {
    @ObservedObject private var manager = RaceGoalManager.shared
    @Environment(\.dismiss) private var dismiss

    // ローカル編集用コピー（保存ボタンで manager.settings に反映）
    @State private var isEnabled:   Bool          = false
    @State private var raceType:    RaceGoalType  = .olympicTri
    @State private var raceDate:    Date          = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var customName:   String = ""
    @State private var customSwimStr = ""
    @State private var customBikeStr = ""
    @State private var customRunStr  = ""
    @State private var customSwimKm: Double = 0
    @State private var customBikeKm: Double = 0
    @State private var customRunKm:  Double = 0

    @State private var showSavedBanner = false

    // 保存済みの設定と現在の編集が異なるか
    private var isDirty: Bool {
        isEnabled   != manager.settings.isEnabled
        || raceType != manager.settings.raceType
        || raceDate != manager.settings.raceDate
        || (raceType == .custom && (
               customName  != manager.settings.customName
            || customSwimKm != manager.settings.customSwimKm
            || customBikeKm != manager.settings.customBikeKm
            || customRunKm  != manager.settings.customRunKm
        ))
    }

    // プレビュー用週次目標（ローカル値から計算）
    private var previewWeeklyGoal: RaceDistances {
        var tmp = RaceGoalSettings()
        tmp.raceType     = raceType
        tmp.raceDate     = raceDate
        tmp.customSwimKm = customSwimKm
        tmp.customBikeKm = customBikeKm
        tmp.customRunKm  = customRunKm
        return tmp.weeklyTrainingGoal()
    }
    private var previewDays:  Int { max(0, Calendar.current.dateComponents([.day],       from: Date(), to: raceDate).day  ?? 0) }
    private var previewWeeks: Int { max(0, Calendar.current.dateComponents([.weekOfYear], from: Date(), to: raceDate).weekOfYear ?? 0) }

    var body: some View {
        Form {
            // MARK: - 有効トグル
            Section {
                Toggle("レース目標を使用する", isOn: $isEnabled)
                    .tint(Color.duoGreen)
            } footer: {
                Text("ONにすると GOALページに週間トレーニング到達度が表示されます。")
                    .font(.caption)
            }

            if isEnabled {
                // MARK: - 種目選択
                Section {
                    ForEach(RaceGoalType.allCases, id: \.self) { type in
                        raceTypeRow(type)
                    }
                } header: {
                    Text("種目")
                }

                // MARK: - カスタム設定
                if raceType == .custom {
                    Section {
                        HStack {
                            Text("🏷 名前")
                                .frame(width: 90, alignment: .leading)
                            TextField("例：スプリント", text: $customName)
                                .multilineTextAlignment(.trailing)
                        }
                        distanceField(label: "🏊 スイム", unit: "km",
                                      text: $customSwimStr, value: $customSwimKm)
                        distanceField(label: "🚴 バイク", unit: "km",
                                      text: $customBikeStr, value: $customBikeKm)
                        distanceField(label: "🏃 ラン",   unit: "km",
                                      text: $customRunStr,  value: $customRunKm)
                    } header: {
                        Text("カスタム設定")
                    } footer: {
                        Text("名前を入力するとGOALページのカードに表示されます。")
                            .font(.caption)
                    }
                }

                // MARK: - 大会日
                Section {
                    DatePicker("大会日", selection: $raceDate,
                               in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                    HStack {
                        Text("大会まで")
                        Spacer()
                        Text(previewDays > 0 ? "\(previewDays)日 (\(previewWeeks)週)" : "本日！")
                            .foregroundColor(previewDays <= 7 ? .orange : Color.duoGreen)
                            .font(.system(size: 14, weight: .bold))
                    }
                } header: {
                    Text("大会日")
                }

                // MARK: - 今週の練習目標（プレビュー）
                Section {
                    if previewWeeklyGoal.swimKm > 0 {
                        weeklyGoalRow(emoji: "🏊", label: "スイム", km: previewWeeklyGoal.swimKm)
                    }
                    if previewWeeklyGoal.bikeKm > 0 {
                        weeklyGoalRow(emoji: "🚴", label: "バイク", km: previewWeeklyGoal.bikeKm)
                    }
                    if previewWeeklyGoal.runKm > 0 {
                        weeklyGoalRow(emoji: "🏃", label: "ラン",   km: previewWeeklyGoal.runKm)
                    }
                } header: {
                    Text("今週の練習目標（プレビュー）")
                } footer: {
                    Text("大会まで\(previewWeeks)週のスケジュールに基づいた目標距離です。")
                        .font(.caption)
                }

                // MARK: - 保存ボタン
                Section {
                    Button {
                        saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            Text(manager.settings.isEnabled ? "変更する" : "目標を設定する")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(isDirty ? Color.duoGreen : Color.duoGreen.opacity(0.4))
                    .disabled(!isDirty)
                }
            }
        }
        .navigationTitle("レース目標設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完了") { dismiss() }
                    .fontWeight(.bold)
            }
        }
        .overlay(alignment: .top) {
            if showSavedBanner {
                saveBanner
            }
        }
        .onAppear { loadFromManager() }
    }

    // MARK: - 種目行

    @ViewBuilder
    private func raceTypeRow(_ type: RaceGoalType) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                raceType = type
            }
        } label: {
            HStack(spacing: 10) {
                Text(type.emoji)
                    .font(.system(size: 20))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .foregroundColor(.primary)
                        .font(.system(size: 15, weight: .medium))
                    if type != .custom {
                        Text(type.distanceDescription.joined(separator: "  "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if raceType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 保存バナー

    private var saveBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text("レース目標を保存しました")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.duoGreen)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func raceTypeRow(emoji: String, label: String, km: Double) -> some View {
        HStack {
            Text("\(emoji) \(label)")
            Spacer()
            Text(km >= 10 ? "\(Int(km)) km" : String(format: "%.1f km", km))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.duoGreen)
        }
    }

    private func weeklyGoalRow(emoji: String, label: String, km: Double) -> some View {
        HStack {
            Text("\(emoji) \(label)")
            Spacer()
            Text(km >= 10 ? "\(Int(km)) km" : String(format: "%.1f km", km))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.duoGreen)
        }
    }

    private func distanceField(label: String, unit: String,
                                text: Binding<String>,
                                value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { newVal in
                    if let d = Double(newVal.replacingOccurrences(of: ",", with: ".")) {
                        value.wrappedValue = d
                    }
                }
            Text(unit)
                .foregroundColor(.secondary)
        }
    }

    private func loadFromManager() {
        let s         = manager.settings
        isEnabled     = s.isEnabled
        raceType      = s.raceType
        raceDate      = s.raceDate
        customName    = s.customName
        customSwimKm  = s.customSwimKm
        customBikeKm  = s.customBikeKm
        customRunKm   = s.customRunKm
        customSwimStr = s.customSwimKm > 0 ? formatDouble(s.customSwimKm) : ""
        customBikeStr = s.customBikeKm > 0 ? formatDouble(s.customBikeKm) : ""
        customRunStr  = s.customRunKm  > 0 ? formatDouble(s.customRunKm)  : ""
    }

    private func saveSettings() {
        var s = manager.settings
        s.isEnabled    = isEnabled
        s.raceType     = raceType
        s.raceDate     = raceDate
        s.customName   = customName
        s.customSwimKm = customSwimKm
        s.customBikeKm = customBikeKm
        s.customRunKm  = customRunKm
        manager.settings = s

        withAnimation(.easeInOut) { showSavedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut) { showSavedBanner = false }
        }
    }

    private func formatDouble(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

#Preview {
    NavigationView { RaceGoalSettingsView() }
}
