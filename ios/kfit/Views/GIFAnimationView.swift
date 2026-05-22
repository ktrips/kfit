import SwiftUI
import UIKit
import ImageIO

/// GIFファイルをアニメーション再生するビュー（iOS）
/// バックグラウンドスレッドでデコードし、メインスレッドで表示
struct GIFAnimationView: UIViewRepresentable {
    let gifName: String
    var contentMode: UIView.ContentMode = .scaleAspectFit

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
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
                  let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return }

            let count = CGImageSourceGetCount(source)
            var images: [UIImage] = []
            var totalDuration: Double = 0

            for i in 0..<count {
                guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                images.append(UIImage(cgImage: cg))
                let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
                let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
                let d = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                totalDuration += max(d, 0.02)
            }

            guard !images.isEmpty else { return }
            let animated = UIImage.animatedImage(with: images, duration: totalDuration)

            DispatchQueue.main.async {
                context.coordinator.imageView?.image = animated
                context.coordinator.imageView?.startAnimating()
            }
        }

        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image != nil && !uiView.isAnimating {
            uiView.startAnimating()
        }
    }
}
