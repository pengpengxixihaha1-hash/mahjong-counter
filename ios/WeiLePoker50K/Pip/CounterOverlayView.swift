import UIKit

// 记牌器浮窗 UI（渲染进 CVPixelBuffer 的画布）：
//   行0：标题「五十K」+ 状态
//   行1：主条 王 2 A K Q J 10 9 8 7 6 5 4 3（分牌 5/10/K 橙色）
//   行2-5：四家流水 对/上/下/我 剩余张数 + 最近出牌紧凑串
// 与 PC 版 counter_gui.py 显示一致。画布 640x420。
final class CounterOverlayView: UIView {
    struct Model: Equatable {
        var status = "识别中..."
        var main: [String: Int] = [:]
        var seats: [IPC.Snapshot.Seat] = []
        var newGame = false
    }

    static let canvasSize = CGSize(width: 640, height: 420)
    static let order = ["JK", "2", "A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3"]
    static let label: [String: String] = ["JK": "王", "T": "10"]

    var model = Model() { didSet { if model != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.canvasSize))
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let dark = UIColor(red: 0.106, green: 0.118, blue: 0.149, alpha: 0.94)  // #1b1e26
    private let labelGray = UIColor(red: 0.545, green: 0.565, blue: 0.627, alpha: 1) // #8a90a0
    private let valueWhite = UIColor.white
    private let scoredOrange = UIColor(red: 1.0, green: 0.722, blue: 0.302, alpha: 1) // #ffb84d
    private let seatBlue = UIColor(red: 0.624, green: 0.769, blue: 0.910, alpha: 1)   // #9fc4e8

    override func draw(_ rect: CGRect) {
        let W = bounds.width, H = bounds.height
        let bg = UIBezierPath(roundedRect: bounds, cornerRadius: 18)
        dark.setFill()
        bg.fill()

        func text(_ s: String, font: UIFont, color: UIColor, at p: CGPoint) {
            (s as NSString).draw(at: p, withAttributes: [
                .font: font, .foregroundColor: color,
            ])
        }

        // 行0：标题 + 状态
        text("五十K", font: .systemFont(ofSize: 17, weight: .semibold), color: labelGray, at: CGPoint(x: 18, y: 10))
        text(model.status, font: .systemFont(ofSize: 12), color: labelGray,
             at: CGPoint(x: W - 200, y: 14))

        // 行1：主条
        let cols = Self.order.count
        let colW = (W - 80) / CGFloat(cols)
        for (i, r) in Self.order.enumerated() {
            let x = 80 + CGFloat(i) * colW
            text(Self.label[r] ?? r, font: .systemFont(ofSize: 13),
                 color: labelGray, at: CGPoint(x: x + colW / 2 - 8, y: 34))
            let left = model.main[r]
            let s = left.map { String($0) } ?? "-"
            let color = CardDefs.scored.contains(r) ? scoredOrange : valueWhite
            text(s, font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold),
                 color: color, at: CGPoint(x: x + colW / 2 - 9, y: 52))
        }

        // 行2-5：四家流水
        let rowY0: CGFloat = 108
        let rowH: CGFloat = (H - rowY0 - 10) / 4
        for (i, seat) in model.seats.enumerated() {
            let y = rowY0 + CGFloat(i) * rowH
            let cards = seat.cards.isEmpty ? "" : "  \(seat.cards)"
            text("\(seat.name) \(seat.left)\(cards)",
                 font: .monospacedDigitSystemFont(ofSize: 19, weight: .regular),
                 color: seatBlue, at: CGPoint(x: 18, y: y + rowH / 2 - 13))
        }
        if model.seats.isEmpty {
            text("等待识别数据…", font: .systemFont(ofSize: 15), color: labelGray,
                 at: CGPoint(x: 18, y: rowY0 + 10))
        }
    }
}
