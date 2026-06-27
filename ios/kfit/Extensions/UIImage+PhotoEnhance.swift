import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - UIImage 写真補正拡張
// アップロード前に「明るく・くっきり・鮮やか」に自動補正する。
// Core Image を使用し、ハードウェアアクセラレーションで高速処理する。

extension UIImage {

    /// 写真をアップロード用に補正する
    /// - Parameters:
    ///   - brightness:   明るさ補正（0 = 変化なし、+0.05 = 少し明るく）
    ///   - contrast:     コントラスト（1.0 = 変化なし、1.08 = 引き締まった印象）
    ///   - saturation:   彩度（1.0 = 変化なし、1.15 = 少し鮮やか）
    ///   - vibrance:     バイブランス（0 = 変化なし、0.25 = 自然な鮮やか）
    ///   - sharpness:    シャープネス（0 = 変化なし、0.35 = 程よいキレ）
    /// - Returns: 補正済み UIImage（失敗時は元画像を返す）
    func enhancedForUpload(
        brightness: Float = 0.04,
        contrast:   Float = 1.06,
        saturation: Float = 1.12,
        vibrance:   Float = 0.22,
        sharpness:  Float = 0.32
    ) -> UIImage {
        guard let cgImage = self.cgImage else { return self }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        var ciImage = CIImage(cgImage: cgImage)

        // ① 自動補正フィルタ（赤目補正・顔の露出補正など）を適用
        let autoFilters = ciImage.autoAdjustmentFilters(options: [
            CIImageAutoAdjustmentOption.enhance: true,
            CIImageAutoAdjustmentOption.redEye:  true
        ])
        for filter in autoFilters {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage { ciImage = output }
        }

        // ② 明るさ・コントラスト・彩度
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage  = ciImage
        colorControls.brightness  = brightness
        colorControls.contrast    = contrast
        colorControls.saturation  = saturation
        if let output = colorControls.outputImage { ciImage = output }

        // ③ バイブランス（すでに鮮やかな色を壊さず、くすんだ色を引き出す）
        let vibranceFilter = CIFilter.vibrance()
        vibranceFilter.inputImage = ciImage
        vibranceFilter.amount     = vibrance
        if let output = vibranceFilter.outputImage { ciImage = output }

        // ④ シャープネス（輝度チャンネルのみ。ノイズを増やさず輪郭を立てる）
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ciImage
        sharpen.sharpness  = sharpness
        sharpen.radius     = 1.69
        if let output = sharpen.outputImage { ciImage = output }

        // CGImage に変換して返す
        guard let outputCG = context.createCGImage(ciImage, from: ciImage.extent) else {
            return self
        }
        return UIImage(cgImage: outputCG, scale: self.scale, orientation: self.imageOrientation)
    }
}
