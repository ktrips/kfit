import SwiftUI
import UIKit

// MARK: - RoundedCorner（角丸を個別指定できる Shape）
// ⚠️ kfit/kedu/KeduStubViews.swift の RoundedCorner と同一実装。
//    KFitCore 追加後はスタブ側を削除する。

public struct RoundedCorner: Shape {
    public var radius: CGFloat = .infinity
    public var corners: UIRectCorner = .allCorners

    public init(radius: CGFloat = .infinity, corners: UIRectCorner = .allCorners) {
        self.radius = radius
        self.corners = corners
    }

    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

public extension View {
    /// 指定したコーナーだけ角丸にするモディファイア
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
