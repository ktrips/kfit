import SwiftUI
import UIKit
import ImageIO

/// GIFファイルをアニメーション再生するビュー（iOS）
/// - フレームはバックグラウンドで「表示サイズにダウンサンプル + 即時デコード」して保持する
///   （UIImageView に生の CGImage を渡すと表示のたびにメインスレッドで展開されてカクつくため）
/// - デコード結果は NSCache に保持し、GIF ローテーションで同じファイルを再デコードしない
/// - 拡大表示時のジャギーを抑えるため trilinear フィルタを使う
struct GIFAnimationView: UIViewRepresentable {
    let gifName: String
    var contentMode: UIView.ContentMode = .scaleAspectFit
    /// 0 = 無限ループ、1以上 = 指定回数再生して最終フレームで停止
    var loopCount: Int = 0
    /// 保持するフレーム上限（超過分は等間隔で間引く）
    var maxFrames: Int = 48

    private struct DecodedGIF {
        let frames: [UIImage]
        let duration: Double
        var cost: Int {
            frames.reduce(0) { $0 + Int($1.size.width * $1.size.height * $1.scale * $1.scale) * 4 }
        }
    }

    /// デコード済み GIF のキャッシュ（メモリ逼迫時は自動解放される）
    private static let cache: NSCache<NSString, AnyObject> = {
        let c = NSCache<NSString, AnyObject>()
        c.totalCostLimit = 64 * 1024 * 1024  // 64MB
        return c
    }()

    private final class CacheEntry {
        let gif: DecodedGIF
        init(_ gif: DecodedGIF) { self.gif = gif }
    }

    final class Coordinator {
        weak var imageView: UIImageView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.minificationFilter = .trilinear
        context.coordinator.imageView = imageView

        let name = gifName
        let loops = loopCount
        let maxF = maxFrames
        let cacheKey = "\(name)#\(maxF)" as NSString

        if let entry = Self.cache.object(forKey: cacheKey) as? CacheEntry {
            apply(entry.gif, to: imageView, loops: loops)
            return imageView
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let gif = Self.decodeGIF(named: name, maxFrames: maxF) else { return }
            Self.cache.setObject(CacheEntry(gif), forKey: cacheKey, cost: gif.cost)
            DispatchQueue.main.async {
                guard let iv = context.coordinator.imageView else { return }
                apply(gif, to: iv, loops: loops)
            }
        }

        return imageView
    }

    private func apply(_ gif: DecodedGIF, to imageView: UIImageView, loops: Int) {
        imageView.image = gif.frames.first
        imageView.animationImages = gif.frames
        imageView.animationDuration = gif.duration
        imageView.animationRepeatCount = loops
        imageView.startAnimating()
    }

    // MARK: デコード

    private static func decodeGIF(named name: String, maxFrames: Int) -> DecodedGIF? {
        guard let data = findGIFData(named: name),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let totalCount = CGImageSourceGetCount(source)
        guard totalCount > 0 else { return nil }

        // フレーム数が上限を超える場合は等間隔に間引くインデックスを計算
        let stride = totalCount > maxFrames
            ? Int(ceil(Double(totalCount) / Double(maxFrames)))
            : 1
        let indices = (0..<totalCount).filter { $0 % stride == 0 }

        // 表示サイズ（画面幅×156pt 程度）を超えない範囲で即時デコード。
        // 元 GIF が小さい場合は等倍のまま（無駄な拡大はしない）。
        let screenScale = UIScreen.main.scale
        let maxPixel = Int(480 * screenScale)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for i in indices {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, thumbOptions as CFDictionary) else { continue }
            images.append(UIImage(cgImage: cg, scale: screenScale, orientation: .up))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let d = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double)
                ?? 0.1
            // 間引いた場合は元の総時間を比例配分して維持
            totalDuration += max(d, 0.02) * Double(stride)
        }

        guard !images.isEmpty else { return nil }
        return DecodedGIF(frames: images, duration: totalDuration)
    }

    private static func findGIFData(named name: String) -> Data? {
        if let asset = NSDataAsset(name: name) {
            return asset.data
        }
        guard let url = findGIFURL(named: name) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func findGIFURL(named name: String) -> URL? {
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
