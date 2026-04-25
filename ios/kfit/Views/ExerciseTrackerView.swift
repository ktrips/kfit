import SwiftUI

struct ExerciseTrackerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var motionManager = MotionDetectionManager()
    @State private var selectedExercise: Exercise?
    @State private var manualRepCount = 0
    @State private var isUsingMotionDetection = false
    @State private var showSuccess = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Close button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 24) {
                        // Exercise selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Exercise")
                                .font(.headline)

                            VStack(spacing: 8) {
                                ForEach(authManager.exercises) { exercise in
                                    Button(action: { selectedExercise = exercise }) {
                                        Text(exercise.name)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                selectedExercise?.id == exercise.id
                                                    ? Color.blue
                                                    : Color(.systemGray5)
                                            )
                                            .foregroundColor(
                                                selectedExercise?.id == exercise.id
                                                    ? .white
                                                    : .black
                                            )
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)

                        // Rep counter
                        if let exercise = selectedExercise {
                            VStack(spacing: 16) {
                                // Rep display
                                VStack(spacing: 12) {
                                    Text("Reps")
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    Text("\(isUsingMotionDetection ? motionManager.repCount : manualRepCount)")
                                        .font(.system(size: 56, weight: .bold))
                                        .foregroundColor(.blue)

                                    if !isUsingMotionDetection {
                                        HStack(spacing: 20) {
                                            Button(action: { if manualRepCount > 0 { manualRepCount -= 1 } }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.red)
                                            }

                                            Button(action: { manualRepCount += 1 }) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .background(Color(.systemGray5))
                                .cornerRadius(12)

                                // Points calculation
                                HStack {
                                    Text("Points earned:")
                                        .font(.headline)

                                    Spacer()

                                    let reps = isUsingMotionDetection ? motionManager.repCount : manualRepCount
                                    Text("\(reps * exercise.basePoints)")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(8)

                                // Form score (if using motion detection)
                                if isUsingMotionDetection {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Form Score:")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            Spacer()

                                            Text("\(Int(motionManager.formScore))%")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                        }

                                        ProgressView(value: motionManager.formScore / 100)
                                            .tint(.green)
                                    }
                                    .padding(12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                }

                                // Motion detection toggle
                                Toggle("Use Motion Detection", isOn: $isUsingMotionDetection)
                                    .onChange(of: isUsingMotionDetection) { _, newValue in
                                        if newValue {
                                            motionManager.startDetection(for: .pushup)
                                        } else {
                                            motionManager.stopDetection()
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                            .padding(20)
                            .background(Color.white)
                            .cornerRadius(12)
                            .padding(.horizontal, 20)

                            // Submit button
                            Button(action: submitWorkout) {
                                Text("✓ Log Workout")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled((isUsingMotionDetection ? motionManager.repCount : manualRepCount) == 0)
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }

            // Success message
            if showSuccess {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)

                        Text("Workout logged successfully!")
                            .font(.headline)
                    }
                    .padding(16)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .padding(20)

                    Spacer()
                }
            }
        }
        .onDisappear {
            motionManager.stopDetection()
        }
    }

    private func submitWorkout() {
        guard let exercise = selectedExercise else { return }

        let reps = isUsingMotionDetection ? motionManager.repCount : manualRepCount
        let formScore = isUsingMotionDetection ? motionManager.formScore : 85.0

        Task {
            await authManager.recordExercise(exercise, reps: reps, formScore: formScore)
            showSuccess = true

            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            dismiss()
        }
    }
}

#Preview {
    ExerciseTrackerView()
        .environmentObject(AuthenticationManager.shared)
}
