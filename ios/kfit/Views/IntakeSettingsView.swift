import SwiftUI

struct IntakeSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var settings = IntakeSettings.defaultSettings
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                // 食事のカロリー設定
                Section {
                    HStack {
                        Text("🌅 朝食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.breakfastCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍱 昼食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.lunchCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍽️ 夕食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dinnerCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("食事のデフォルトカロリー")
                }

                // 水分設定
                Section {
                    HStack {
                        Text("💧 水1杯")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.waterPerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("水分")
                }

                // コーヒー設定
                Section {
                    HStack {
                        Text("☕ コーヒー1杯")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.coffeePerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("カフェイン量")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.caffeinePerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mg")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("コーヒー")
                }

                // 1日の目標値
                Section {
                    HStack {
                        Text("🎯 カロリー目標")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyCalorieGoal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("💧 水分目標")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyWaterGoal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("☕ カフェイン上限")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyCaffeineLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mg")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍺 アルコール上限")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyAlcoholLimit, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("1日の目標")
                }

                // アルコール設定
                Section {
                    ForEach($settings.alcoholSettings) { $alcoholSetting in
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(alcoholSetting.type.emoji) \(alcoholSetting.displayName)")
                                    .font(.subheadline).fontWeight(.bold)
                                Spacer()
                            }

                            HStack {
                                Text("量")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                                Spacer()
                                TextField("", value: $alcoholSetting.amountMl, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("ml")
                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                            }

                            HStack {
                                Text("アルコール")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                                Spacer()
                                TextField("", value: $alcoholSetting.alcoholG, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("g")
                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("アルコール")
                }

                // リセットボタン
                Section {
                    Button {
                        settings = IntakeSettings.defaultSettings
                    } label: {
                        HStack {
                            Spacer()
                            Text("デフォルトに戻す")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoOrange)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("摂取記録設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            isSaving = true
                            await authManager.saveIntakeSettings(settings)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                settings = await authManager.getIntakeSettings()
                isLoading = false
            }
        }
    }
}

#Preview {
    IntakeSettingsView()
        .environmentObject(AuthenticationManager.shared)
}
