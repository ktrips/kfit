import SwiftUI
import AVFoundation

/// mp4動画をミュート・無限ループ再生するビュー（iOS）
/// GIFAnimationView（フレームを全展開してUIImageViewでアニメーション）の後継。
/// AVPlayerLooperによるハードウェアデコード再生のため、フレーム展開によるメモリ消費が発生しない。
struct LoopingVideoView: UIViewRepresentable {
    let videoName: String
    var contentMode: UIView.ContentMode = .scaleAspectFit

    final class PlayerContainerView: UIView {
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(name: String, contentMode: UIView.ContentMode) {
            guard let url = Self.findVideoURL(named: name) else { return }
            playerLayer.videoGravity = contentMode == .scaleAspectFill ? .resizeAspectFill : .resizeAspect

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            self.queuePlayer = player
            self.looper = looper
            player.play()
        }

        func pause() {
            queuePlayer?.pause()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        private static func findVideoURL(named name: String) -> URL? {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Videos") {
                return url
            }
            return Bundle.main.url(forResource: name, withExtension: "mp4")
        }
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(name: videoName, contentMode: contentMode)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.pause()
    }
}
