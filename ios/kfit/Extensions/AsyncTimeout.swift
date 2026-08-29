import Foundation

/// 指定秒数以内に `operation` が完了しなければ `defaultValue` を返す。
/// Firestore の `getDocument()` や HealthKit の `withCheckedContinuation` ラップなど、
/// completion ハンドラが一度も呼ばれないまま `await` が無期限にハングしうる呼び出しを
/// 保護するために使う。タイムアウト側が勝った場合、元の `operation` はキャンセルされず
/// 裏で動き続ける（HealthKit のクエリ自体を止める手段がないため）が、呼び出し元は
/// 解放されて isLoading 等の状態を正しく戻せる。
func withTimeout<T>(
    seconds: TimeInterval,
    default defaultValue: T,
    operation: @escaping @Sendable () async -> T
) async -> T {
    await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        let box = TimeoutResumeBox(continuation)
        Task {
            let result = await operation()
            await box.resume(result)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await box.resume(defaultValue)
        }
    }
}

/// `CheckedContinuation` は2回目以降の resume で assert 落ちするため、
/// 最初の1回だけ通す簡易ガード。
private actor TimeoutResumeBox<T> {
    private var didResume = false
    private let continuation: CheckedContinuation<T, Never>

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
