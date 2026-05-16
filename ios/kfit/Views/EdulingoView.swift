import SwiftUI

struct EdulingoView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("edulingo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("Edulingo")
                .font(.title).fontWeight(.bold)
                .foregroundColor(Color.duoDark)

            Text("Coming Soon")
                .font(.body)
                .foregroundColor(Color.duoSubtitle)

            Spacer()
        }
        .navigationTitle("Edulingo")
    }
}
