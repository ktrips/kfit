import SwiftUI
import ImageIO

@MainActor
private enum WatchGIFFrameCache {
    struct Entry {
        let frames: [CGImage]
        let delays: [Double]
    }

    private static var entries: [String: Entry] = [:]

    static func entry(for resourceName: String) -> Entry? {
        entries[resourceName]
    }

    static func store(_ entry: Entry, for resourceName: String) {
        entries[resourceName] = entry
    }
}

/// GIFファイルをアニメーション再生するビュー（watchOS — CGImage + Timer）
struct GIFAnimationView: View {
    @State private var frames: [CGImage] = []
    @State private var delays: [Double] = []
    @State private var currentIndex: Int = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if !frames.isEmpty {
                Image(decorative: frames[currentIndex], scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .onAppear { loadGIF() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func loadGIF() {
        let resourceName = "fitingo_workout"
        if let cached = WatchGIFFrameCache.entry(for: resourceName) {
            frames = cached.frames
            delays = cached.delays
            guard !frames.isEmpty else { return }
            scheduleNext()
            return
        }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return }

        let count = CGImageSourceGetCount(source)
        var imgs: [CGImage] = []
        var dlys: [Double] = []

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            imgs.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let d = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double)
                ?? 0.1
            dlys.append(max(d, 0.02))
        }

        frames = imgs
        delays = dlys
        WatchGIFFrameCache.store(WatchGIFFrameCache.Entry(frames: imgs, delays: dlys), for: resourceName)
        guard !frames.isEmpty else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        guard !frames.isEmpty else { return }
        let delay = delays.isEmpty ? 0.1 : delays[currentIndex % delays.count]
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            currentIndex = (currentIndex + 1) % frames.count
            scheduleNext()
        }
    }
}
