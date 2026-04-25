import SwiftUI
import WatchKit

struct WatchQuickWorkoutView: View {
    @Binding var isPresented: Bool
    @StateObject private var motionManager = WatchMotionDetectionManager()
    @State private var selectedExerciseType: ExerciseType = .pushup
    @State private var isUsingMotion = true
    @State private var manualRepCount = 0
    @State private var showCalibration = false
    @State private var isCalibrating = false

    var body: some View {
        TabView {
            // Exercise selection
            VStack(spacing: 12) {
                Text("Exercise")
                    .font(.headline)

                Picker("Exercise", selection: $selectedExerciseType) {
                    ForEach(ExerciseType.allCases, id: \.self) { type in
                        Text("\(type.icon) \(type.rawValue)").tag(type)
                    }
                }
                .pickerStyle(.wheel)

                Spacer()

                if !motionManager.isDetecting {
                    Button(action: startWorkout) {
                        Text("Start")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
            }
            .padding()

            // Rep counter and form
            if motionManager.isDetecting {
                VStack(spacing: 10) {
                    // Rep count (large)
                    VStack(spacing: 4) {
                        Text("Reps")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        Text("\(isUsingMotion ? motionManager.repCount : manualRepCount)")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    // Form score
                    if isUsingMotion {
                        VStack(spacing: 4) {
                            Text("Form")
                                .font(.caption2)
                                .foregroundColor(.gray)

                            HStack(spacing: 4) {
                                Image(systemName: motionManager.formScore > 80 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(motionManager.formScore > 80 ? .green : .orange)

                                Text("\(Int(motionManager.formScore))%")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                        }
                    }

                    Spacer()

                    // Manual controls (if not using motion)
                    if !isUsingMotion {
                        HStack(spacing: 8) {
                            Button(action: { if manualRepCount > 0 { manualRepCount -= 1 } }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red)
                            }

                            Button(action: { manualRepCount += 1 }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: finishWorkout) {
                            Text("✓ Done")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }

                        Button(action: cancelWorkout) {
                            Text("✕")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding(.vertical, 6)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
            }

            // Settings
            VStack(spacing: 12) {
                Text("Settings")
                    .font(.headline)

                Toggle("Motion Detect", isOn: $isUsingMotion)
                    .onChange(of: isUsingMotion) { _, newValue in
                        if newValue && !motionManager.isDetecting {
                            showCalibration = true
                        }
                    }

                if isUsingMotion {
                    Button(action: { showCalibration = true }) {
                        Text("Calibrate")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }

                Spacer()

                Text(motionManager.isDetecting ? "Detecting..." : "Ready")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding()
            .sheet(isPresented: $showCalibration) {
                CalibrationView(isPresented: $showCalibration, motionManager: motionManager)
            }
        }
        .tabViewStyle(.page)
    }

    private func startWorkout() {
        if isUsingMotion {
            motionManager.startDetection(for: selectedExerciseType)
        } else {
            motionManager.isDetecting = true
            manualRepCount = 0
        }
    }

    private func finishWorkout() {
        motionManager.stopDetection()
        // Send to iOS app via Watch Connectivity
        isPresented = false
    }

    private func cancelWorkout() {
        motionManager.stopDetection()
        manualRepCount = 0
        isPresented = false
    }
}

struct CalibrationView: View {
    @Binding var isPresented: Bool
    let motionManager: WatchMotionDetectionManager
    @State private var isCalibrating = false
    @State private var countDown = 3

    var body: some View {
        VStack(spacing: 16) {
            Text("Calibration")
                .font(.headline)

            if !isCalibrating {
                VStack(spacing: 12) {
                    Text("Hold watch still on a flat surface")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)

                    Button(action: startCalibration) {
                        Text("Start")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Hold still...")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("\(countDown)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.orange)
                        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                            if countDown > 1 {
                                countDown -= 1
                            } else {
                                isCalibrating = false
                                isPresented = false
                            }
                        }
                }
            }

            Spacer()

            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .background(Color.gray)
                    .cornerRadius(4)
            }
        }
        .padding()
    }

    private func startCalibration() {
        isCalibrating = true
        countDown = 3
        motionManager.calibrate()
    }
}

#Preview {
    WatchQuickWorkoutView(isPresented: .constant(true))
}

#Preview {
    WatchQuickWorkoutView(isPresented: .constant(true))
}
