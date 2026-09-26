import Foundation

// 微乐五十K 牌定义 —— iOS 版为「牌点-only」口径（用户明确不分花色）。
// 两副牌 108 张 = 13 点 × 8 + 王 × 4；每家 27 张起步。
public enum CardDefs {
    /// 点数升序（3 最小，JK 最大）
    public static let ranks = ["3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A", "2", "JK"]
    /// 分牌：5 / 10 / K
    public static let scored: Set<String> = ["5", "T", "K"]
    /// 每点总张数（基数夹逼保险丝用）：王 4，其余 8
    public static func rankTotal(_ rank: String) -> Int { rank == "JK" ? 4 : 8 }
    /// 流水串排序键（JK 最后）
    public static func sortKey(_ rank: String) -> Int {
        ranks.firstIndex(of: rank) ?? 0
    }
    /// 流水紧凑字符：王→W、10→0，其余取首字符
    public static func compact(_ rank: String) -> String {
        if rank == "JK" { return "W" }
        return rank == "T" ? "0" : rank
    }
}

/// 单张检出（识别结果）：cls 为牌点（"3".."2"、"JK"）
public struct CardDetection {
    public var cls: String
    public var score: Double
    public var x: Int
    public var y: Int

    public init(cls: String, score: Double, x: Int, y: Int) {
        self.cls = cls
        self.score = score
        self.x = x
        self.y = y
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
