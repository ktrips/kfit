import SwiftUI
import Combine

// MARK: - TomatoWedge（断面セグメント）

private struct TomatoWedge: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let r     = min(rect.width, rect.height) / 2.0 * 0.93
        let inner = r * 0.22
        let step  = 2.0 * .pi / 8.0
        let gap   = step * 0.065
        let s     = step * Double(index) - .pi / 2.0 + gap
        let e     = s + step - gap * 2.0
        p.move(to: CGPoint(x: cx + inner * cos(s), y: cy + inner * sin(s)))
        p.addLine(to: CGPoint(x: cx + r * cos(s), y: cy + r * sin(s)))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .radians(s), endAngle: .radians(e), clockwise: false)
        p.addLine(to: CGPoint(x: cx + inner * cos(e), y: cy + inner * sin(e)))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: inner,
                 startAngle: .radians(e), endAngle: .radians(s), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - TomatoVeins（断面の放射状仕切り線）

private struct TomatoVeins: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let r     = min(rect.width, rect.height) / 2.0 * 0.93
        let inner = r * 0.22
        for i in 0..<8 {
            let a = 2.0 * .pi / 8.0 * Double(i) - .pi / 2.0
            p.move(to: CGPoint(x: cx + inner * cos(a), y: cy + inner * sin(a)))
            p.addLine(to: CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
        }
        return p
    }
}

// MARK: - LargeTomatoView（プログレッシブ断面ビュー revealedSlices: 0〜8）

struct LargeTomatoView: View {
    let revealedSlices: Int
    var pulse: Bool = false

    private let fleshColor = Color(red: 1.00, green: 0.62, blue: 0.22)
    private let paleColor  = Color(red: 0.97, green: 0.91, blue: 0.89)
    private let coreColor  = Color(red: 0.96, green: 0.90, blue: 0.68)
    private let stemGreen  = Color(red: 0.15, green: 0.58, blue: 0.09)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.97, green: 0.33, blue: 0.18),
                                 Color(red: 0.64, green: 0.09, blue: 0.04)],
                        startPoint: UnitPoint(x: 0.35, y: 0.15),
                        endPoint: .bottomTrailing
                    ))
                    .scaleEffect(pulse ? 1.013 : 0.992)
                    .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: pulse)

                ForEach(0..<8, id: \.self) { i in
                    TomatoWedge(index: i)
                        .fill(i < revealedSlices
                              ? fleshColor.opacity(0.92)
                              : paleColor.opacity(0.16))
                        .animation(.easeIn(duration: 0.55), value: revealedSlices)
                }

                TomatoVeins()
                    .stroke(Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.4))

                Canvas { ctx, csz in
                    let hw   = Double(csz.width)  / 2.0
                    let hh   = Double(csz.height) / 2.0
                    let dist = Double(s) * 0.305
                    let sr   = Double(s) * 0.023
                    let sep  = Double(s) * 0.038
                    let shd  = GraphicsContext.Shading.color(
                        Color(red: 0.95, green: 0.88, blue: 0.58))
                    for i in 0..<min(revealedSlices, 8) {
                        let mid  = (Double(i) * 45.0 - 90.0 + 22.5) * .pi / 180.0
                        let perp = mid + .pi / 2.0
                        let bcx  = hw + dist * cos(mid)
                        let bcy  = hh + dist * sin(mid)
                        for d in [-1.0, 0.0, 1.0] {
                            let px = bcx + cos(perp) * sep * d
                            let py = bcy + sin(perp) * sep * d
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: px - sr, y: py - sr,
                                                      width: sr * 2, height: sr * 2)),
                                with: shd)
                        }
                    }
                }
                .frame(width: s, height: s)

                Circle()
                    .fill(coreColor)
                    .overlay(Circle().stroke(Color.white.opacity(0.40), lineWidth: 1))
                    .frame(width: s * 0.22, height: s * 0.22)

                Group {
                    Capsule()
                        .fill(stemGreen)
                        .frame(width: s * 0.048, height: s * 0.078)
                        .offset(y: -(s * 0.465))
                    ForEach([-1, 0, 1], id: \.self) { n in
                        Ellipse()
                            .fill(stemGreen)
                            .frame(width: s * 0.096, height: s * 0.050)
                            .rotationEffect(.degrees(Double(n) * 40.0))
                            .offset(y: -(s * 0.448))
                    }
                }

                Ellipse()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: s * 0.29, height: s * 0.17)
                    .offset(x: -s * 0.10, y: -s * 0.20)
                    .blendMode(.screen)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - TomatoHalf（完了時の割れたトマト演出用）

struct TomatoHalf: View {
    let isLeft: Bool

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.height
            LargeTomatoView(revealedSlices: 8, pulse: false)
                .frame(width: side, height: side)
                .offset(x: isLeft ? 0 : -(side / 2.0))
        }
        .clipped()
    }
}

// MARK: - StandPomodoroView（20分ポモドーロタイマー）

struct StandPomodoroView: View {
    @Environment(\.dismiss) private var dismiss

    let durationSeconds: Int
    let onComplete: () -> Void

    @State private var remainingSeconds: Int
    @State private var timerFinished  = false
    @State private var showCompletion = false
    @State private var pulse          = false
    @State private var splitOffset: CGFloat = 0
    @State private var hapticTimer: Timer?

    init(durationSeconds: Int = 20 * 60, onComplete: @escaping () -> Void) {
        self.durationSeconds = durationSeconds
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: durationSeconds)
    }

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let tomatoRed   = Color(red: 0.86, green: 0.17, blue: 0.09)
    private let tomatoSkin  = Color(red: 0.94, green: 0.28, blue: 0.15)
    private let doneGreen   = Color(red: 0.15, green: 0.72, blue: 0.38)

    private var revealedSlices: Int {
        guard durationSeconds > 0 else { return 0 }
        return min(8, elapsedSeconds * 8 / durationSeconds)
    }
    private var elapsedSeconds: Int { durationSeconds - remainingSeconds }
    private var progress: Double {
        durationSeconds > 0 ? Double(elapsedSeconds) / Double(durationSeconds) : 0
    }
    private var timeText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.99, green: 0.97, blue: 0.95),
                         Color(red: 0.97, green: 0.90, blue: 0.87)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if !showCompletion { timerScreen } else { completionScreen }
        }
        .onAppear { pulse = true }
        .onReceive(ticker) { _ in
            guard !timerFinished else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                timerFinished  = true
                showCompletion = true
                startCompletionHaptics()
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) {
                    splitOffset = 48
                }
            }
        }
        .onDisappear { stopHaptics() }
    }

    // MARK: - タイマー進行画面

    private var timerScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15 * UIScale.font, weight: .bold))
                        .foregroundColor(tomatoRed.opacity(0.42))
                        .padding(10)
                        .background(tomatoSkin.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text("20分ポモドーロ")
                    .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(tomatoRed)
                    .tracking(1.5)
                Text("20分間スマホを触らず、作業に集中！")
                    .font(.system(size: 13 * UIScale.font, weight: .semibold, design: .rounded))
                    .foregroundColor(tomatoRed.opacity(0.62))
            }
            .padding(.top, 4)
            .padding(.bottom, 10)

            GeometryReader { geo in
                let side = min(geo.size.width * 0.78, geo.size.height * 0.86)
                let ringW: CGFloat = 12
                let ringR = side / 2 + ringW / 2 + 5
                ZStack {
                    Circle()
                        .stroke(tomatoSkin.opacity(0.18), lineWidth: ringW)
                        .frame(width: ringR * 2, height: ringR * 2)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.70, blue: 0.20),
                                    tomatoSkin,
                                    tomatoRed,
                                    tomatoRed
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: ringW, lineCap: .round)
                        )
                        .frame(width: ringR * 2, height: ringR * 2)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1.0), value: progress)

                    if progress > 0 && progress < 1 {
                        let angle = (progress * 360 - 90) * .pi / 180
                        Circle()
                            .fill(tomatoRed)
                            .frame(width: ringW * 0.9, height: ringW * 0.9)
                            .shadow(color: tomatoRed.opacity(0.5), radius: 3)
                            .offset(
                                x: CGFloat(cos(angle)) * ringR,
                                y: CGFloat(sin(angle)) * ringR
                            )
                            .animation(.linear(duration: 1.0), value: progress)
                    }

                    LargeTomatoView(revealedSlices: revealedSlices, pulse: pulse)
                        .frame(width: side, height: side)

                    VStack(spacing: 2) {
                        Text(timeText)
                            .font(.system(size: side * 0.145, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.28), radius: 3, y: 1)
                            .monospacedDigit()
                        Text("\(revealedSlices)/8 スライス")
                            .font(.system(size: side * 0.062, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.82))
                            .shadow(color: Color.black.opacity(0.22), radius: 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(tomatoSkin)
                    Text("立って作業すれば集中力・代謝がもっとアップ！")
                        .font(.system(size: 12 * UIScale.font, weight: .medium, design: .rounded))
                        .foregroundColor(tomatoRed.opacity(0.5))
                }
                HStack(spacing: 5) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(tomatoSkin)
                    Text("20分集中したら、5分休憩でリラックス")
                        .font(.system(size: 12 * UIScale.font, weight: .medium, design: .rounded))
                        .foregroundColor(tomatoRed.opacity(0.5))
                }
            }
            .padding(.bottom, 14)

            Button { finishAndRecord() } label: {
                Text("中断する")
                    .font(.system(size: 13 * UIScale.font, weight: .medium, design: .rounded))
                    .foregroundColor(tomatoRed.opacity(0.45))
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 38)
        }
    }

    // MARK: - 完了画面

    private var completionScreen: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("🎉 20分完了！")
                .font(.system(size: 28 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(tomatoRed)

            HStack(alignment: .center, spacing: splitOffset) {
                TomatoHalf(isLeft: true)
                    .frame(width: 108, height: 216)
                    .rotationEffect(.degrees(-11))
                TomatoHalf(isLeft: false)
                    .frame(width: 108, height: 216)
                    .rotationEffect(.degrees(11))
            }
            .frame(height: 240)

            Text("お疲れ様でした！\n立ち仕事でよく頑張りました 🍅")
                .font(.system(size: 14 * UIScale.font, weight: .semibold, design: .rounded))
                .foregroundColor(tomatoRed.opacity(0.60))
                .multilineTextAlignment(.center)

            Spacer()

            Button { finishAndRecord() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18 * UIScale.font, weight: .bold))
                    Text("記録して閉じる")
                        .font(.system(size: 17 * UIScale.font, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(colors: [doneGreen, Color(red: 0.08, green: 0.55, blue: 0.28)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(18)
                .shadow(color: doneGreen.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }

    // MARK: - ハプティクス・記録

    private func startCompletionHaptics() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { stopHaptics() }
    }

    private func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }

    private func finishAndRecord() {
        stopHaptics()
        onComplete()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}
