import Foundation

/// リリースビルドでログ出力を完全に無効化するユーティリティ。
/// `print()` の代わりに `dlog()` を使うことでリリース時のオーバーヘッドをゼロにする。
@inline(__always)
func dlog(_ message: @autoclosure () -> String,
          file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    print("[\(filename):\(line)] \(message())")
    #endif
}
