import SwiftUI

struct WatchDashboardView: View {
    @State private var streak = 5
    @State private var todayPoints = 240
    @State private var todayReps = 45
    @State private var showWorkoutSheet = false
    @State private var recentWorkouts: [String] = ["20 Push-ups", "15 Squats"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Title
                Text("kfit")
                    .font(.headline)
                    .fontWeight(.bold)

                // Quick stats (compact for watch)
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        Text("🔥")
                            .font(.caption)
                        Text("\(streak)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 30)

                    VStack(spacing: 2) {
                        Text("🏆")
                            .font(.caption)
                        Text("\(todayPoints)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 30)

                    VStack(spacing: 2) {
                        Text("💪")
                            .font(.caption)
                        Text("\(todayReps)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(6)
                .background(Color(.systemGray5))
                .cornerRadius(4)

                Divider()
                    .padding(.vertical, 2)

                // Start workout button (prominent)
                Button(action: { showWorkoutSheet = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                        Text("Start")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }

                // Recent workouts
                if !recentWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        ForEach(recentWorkouts, id: \.self) { workout in
                            Text(workout)
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Workouts")
            .sheet(isPresented: $showWorkoutSheet) {
                WatchQuickWorkoutView(isPresented: $showWorkoutSheet)
            }
        }
    }
}

#Preview {
    WatchDashboardView()
}
