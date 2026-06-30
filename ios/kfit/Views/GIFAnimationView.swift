import SwiftUI
import UIKit
import ImageIO

/// GIFファイルをアニメーション再生するビュー（iOS）
/// バックグラウンドスレッドでデコードし、メインスレッドで表示。
/// フレーム数を maxFrames 以下に間引くことで、大容量 GIF でのメモリ消費を抑制する。
struct GIFAnimationView: UIViewRepresentable {
    let gifName: String
    var contentMode: UIView.ContentMode = .scaleAspectFit
    /// 0 = 無限ループ、1以上 = 指定回数再生して最終フレームで停止
    var loopCount: Int = 0
    /// 保持するフレーム上限（超過分は等間隔で間引く）。30フレームで十分滑らか。
    var maxFrames: Int = 30

    final class Coordinator {
        weak var imageView: UIImageView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        context.coordinator.imageView = imageView

        let name = gifName
        let loops = loopCount
        let maxF = maxFrames
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = findGIFData(named: name),
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return }

            let totalCount = CGImageSourceGetCount(source)
            guard totalCount > 0 else { return }

            // フレーム数が上限を超える場合は等間隔に間引くインデックスを計算
            let stride = totalCount > maxF
                ? Int(ceil(Double(totalCount) / Double(maxF)))
                : 1
            let indices = (0..<totalCount).filter { $0 % stride == 0 }

            var images: [UIImage] = []
            var totalDuration: Double = 0

            for i in indices {
                guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                // scale: 0 でスクリーン解像度に自動適応（不要な高解像度展開を回避）
                images.append(UIImage(cgImage: cg, scale: 0, orientation: .up))
                let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
                let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
                let d = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                // 間引いた場合は元の総時間を比例配分して維持
                totalDuration += max(d, 0.02) * Double(stride)
            }

            guard !images.isEmpty else { return }

            DispatchQueue.main.async {
                guard let iv = context.coordinator.imageView else { return }
                iv.image = images.first
                iv.animationImages = images
                iv.animationDuration = totalDuration
                iv.animationRepeatCount = loops
                iv.startAnimating()
            }
        }

        return imageView
    }

    private func findGIFData(named name: String) -> Data? {
        if let asset = NSDataAsset(name: name) {
            return asset.data
        }
        guard let url = findGIFURL(named: name) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func findGIFURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "Images") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
            return url
        }

        guard let enumerator = FileManager.default.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let targetFileName = "\(name).gif"
        for case let url as URL in enumerator where url.lastPathComponent == targetFileName {
            return url
        }
        return nil
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image != nil && !uiView.isAnimating && loopCount == 0 {
            uiView.startAnimating()
        }
    }
}
