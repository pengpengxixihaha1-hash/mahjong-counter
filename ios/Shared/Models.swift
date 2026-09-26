import Foundation

// 微乐五十K 牌定义（与 PC 版 recognize_fiftyk.py 完全一致）
// 两副牌 108 张 = 54 类 × 2（王 JK ×4）；每家 27 张起步。
public enum CardDefs {
    /// 点数升序（3 最小，JK 最大）
    public static let ranks = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2", "JK"]
    public static let suits = ["S", "H", "C", "D"]
    /// 分牌：5 / 10 / K
    public static let scored: Set<String> = ["5", "T", "K"]
    /// 每类基数：王 4 张，其余花色级 2 张
    public static func base(_ cls: String) -> Int { cls == "JK" ? 4 : 2 }
    /// 每点总张数：王 4，其余 4 花色 × 2 = 8（主条显示口径）
    public static func rankTotal(_ rank: String) -> Int { rank == "JK" ? 4 : 8 }

    /// 类名 → 牌点（"JK" → "JK"，"TS" → "T"）
    public static func rankOf(_ cls: String) -> String {
        cls == "JK" ? "JK" : String(cls.prefix(1))
    }
    /// 类名在流水串中的排序键（JK 最后）
    public static func sortKey(_ cls: String) -> Int {
        if cls == "JK" { return 13 }
        return ranks.firstIndex(of: String(cls.prefix(1))) ?? 0
    }
    /// 流水紧凑字符：王→W、10→0，其余取首字符
    public static func compact(_ cls: String) -> String {
        if cls == "JK" { return "W" }
        let c = String(cls.prefix(1))
        return c == "T" ? "0" : c
    }
}

/// 单张检出（识别结果）：花色确定类如 "3S"，星标/伙章牌花色不可判、只按牌点计
public struct CardDetection {
    public var cls: String      // "JK" 或 "3S".."2D"
    public var score: Double
    public var x: Int
    public var y: Int
    public var star: Bool

    public init(cls: String, score: Double, x: Int, y: Int, star: Bool = false) {
        self.cls = cls
        self.score = score
        self.x = x
        self.y = y
        self.star = star
    }
}

/// 多重计数器：对齐 Python collections.Counter 的加法（逐键求和）与并集（逐键取最大）
public struct Counter: Equatable {
    public var d: [String: Int] = [:]

    public init() {}
    public init(_ dict: [String: Int]) { d = dict }

    public mutating func add(_ k: String, _ n: Int = 1) { d[k, default: 0] += n }
    public func get(_ k: String) -> Int { d[k] ?? 0 }
    public var isEmpty: Bool { d.isEmpty }
    public var total: Int { d.values.reduce(0, +) }

    public static func + (a: Counter, b: Counter) -> Counter {
        var r = a
        for (k, v) in b.d { r.d[k, default: 0] += v }
        return r
    }
    public static func += (a: inout Counter, b: Counter) {
        for (k, v) in b.d { a.d[k, default: 0] += v }
    }
    /// 并集（Counter | Counter）：逐键取最大，用于多帧吸收窗口
    public static func |= (a: inout Counter, b: Counter) {
        for (k, v) in b.d { a.d[k] = max(a.get(k), v) }
    }
}
