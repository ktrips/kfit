import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps = 0
    @State private var totalPoints = 0
    @State private var showExerciseTracker = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome, \(authManager.userProfile?.username ?? "User")!")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Keep building your streak!")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // Stats cards
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Streak",
                                value: "\(authManager.userProfile?.streak ?? 0)",
                                icon: "🔥",
                                color: .orange
                            )

                            StatCard(
                                title: "Today's Reps",
                                value: "\(totalReps)",
                                icon: "⚡",
                                color: .green
                            )

                            StatCard(
                                title: "Points",
                                value: "\(totalPoints)",
                                icon: "🏆",
                                color: .blue
                            )
                        }
                        .padding(.horizontal, 20)

                        // Today's workouts
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Today's Workouts")
                                .font(.headline)
                                .padding(.horizontal, 20)

                            if todayExercises.isEmpty {
                                VStack(spacing: 12) {
                                    Text("No workouts logged yet")
                                        .foregroundColor(.gray)

                                    NavigationLink(destination: ExerciseTrackerView()) {
                                        Text("Log Your First Workout")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(todayExercises) { exercise in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(exercise.exerciseName)
                                                    .font(.headline)

                                                Text("\(exercise.reps) reps")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text("\(exercise.points)")
                                                    .font(.headline)
                                                    .foregroundColor(.blue)

                                                Text("points")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(8)
                                    }

                                    NavigationLink(destination: ExerciseTrackerView()) {
                                        Text("+ Log Another Workout")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            }
                        }

                        // 3-month goal
                        VStack(alignment: .leading, spacing: 12) {
                            Text("3-Month Goal")
                                .font(.headline)
                                .padding(.horizontal, 20)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Build a fitness habit and complete your 3-month challenge")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                HStack {
                                    Text("Days Exercised:")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(authManager.userProfile?.streak ?? 0) / 90")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .foregroundColor(Color(.systemGray5))

                                        Capsule()
                                            .foregroundColor(.blue)
                                            .frame(
                                                width: geometry.size.width * CGFloat(Double(authManager.userProfile?.streak ?? 0) / 90)
                                            )
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                }

                // Navigation button
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        NavigationLink(destination: ExerciseTrackerView()) {
                            Label("Log Workout", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: signOut) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.headline)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        todayExercises = await authManager.getTodayExercises()
        totalReps = todayExercises.reduce(0) { $0 + $1.reps }
        totalPoints = todayExercises.reduce(0) { $0 + $1.points }
        isLoading = false
    }

    private func signOut() {
        authManager.signOut()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 24))

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
