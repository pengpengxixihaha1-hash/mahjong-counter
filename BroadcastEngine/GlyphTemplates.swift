import Foundation
import CoreGraphics
import UIKit

/// 内置牌面识别模板：用系统字体把 14 种牌的点数渲染成位图，
/// 二值化归一化后与截屏角标墨迹做归一化相关匹配（颜色无关）。
struct GlyphTemplate {
    let rank: PokerRank
    let data: [Float]   // 40×52，均值0方差1
}

enum GlyphTemplates {

    static let glyphW = 40
    static let glyphH = 52

    private static let templates: [GlyphTemplate] = build()

    static func all() -> [GlyphTemplate] { templates }

    private static func build() -> [GlyphTemplate] {
        let fonts: [(UIFont, String)] = [
            (UIFont.boldSystemFont(ofSize: 100), "bold"),
            (UIFont.systemFont(ofSize: 100), "reg"),
            (UIFont(name: "Georgia-Bold", size: 100) ?? .boldSystemFont(ofSize: 100), "serif"),
        ]
        var out: [GlyphTemplate] = []
        for rank in PokerRank.displayOrder {
            let label = rank.glyph
            for (font, _) in fonts {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black,
                ]
                let text = (label as NSString).size(withAttributes: attrs)
                let cw = max(60, Int(text.width) + 40)
                let ch = max(80, Int(text.height) + 40)
                guard let ctx = CGContext(data: nil, width: cw, height: ch,
                                          bitsPerComponent: 8, bytesPerRow: cw * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
                // CoreGraphics 原点左下，绘制时翻转
                ctx.saveGState()
                ctx.translateBy(x: 0, y: CGFloat(ch))
                ctx.scaleBy(x: 1, y: -1)
                (label as NSString).draw(
                    in: CGRect(x: 0, y: CGFloat(ch) / 2 - text.height / 2, width: CGFloat(cw), height: text.height),
                    withAttributes: attrs)
                ctx.restoreGState()

                guard let cg = ctx.makeImage(),
                      let data = cg.dataProvider?.data,
                      let bytes = CFDataGetBytePtr(data) else { continue }

                // 转灰度帧
                var px = [UInt8](repeating: 0, count: cw * ch)
                for i in 0..<(cw * ch) {
                    let off = i * 4
                    let r = Int(bytes[off]), g = Int(bytes[off + 1]), b = Int(bytes[off + 2])
                    px[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
                }
                let frame = GrayFrame(w: cw, h: ch, px: px)
                // 墨迹紧裁剪：临时 blob = 全图
                var minX = cw, maxX = 0, minY = ch, maxY = 0
                for y in 0..<ch {
                    let row = y * cw
                    for x in 0..<cw where px[row + x] < 165 {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
                guard maxX > minX, maxY > minY else { continue }
                let blob = Blob(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1, area: 1)
                if let norm = ImgProc.normalizedGlyph(frame, blob: blob, outW: glyphW, outH: glyphH) {
                    out.append(GlyphTemplate(rank: rank, data: norm))
                }
            }
        }
        return out
    }
}
