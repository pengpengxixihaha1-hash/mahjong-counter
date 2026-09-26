import CoreVideo
import UIKit

// UI → CVPixelBuffer：把浮窗视图画成 BGRA 视频帧，喂给 PiP 的 SampleBufferDisplayLayer。
final class BufferRenderer {
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        return status == kCVReturnSuccess ? pb : nil
    }

    /// 视图快照 → CGImage（scale=1，保证 1:1 像素）
    func snapshot(view: UIView) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        return image.cgImage
    }

    func render(view: UIView) -> CVPixelBuffer? {
        guard let cg = snapshot(view: view) else { return nil }
        let w = cg.width, h = cg.height
        guard let pb = makePixelBuffer(width: w, height: h) else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pb
    }
}
