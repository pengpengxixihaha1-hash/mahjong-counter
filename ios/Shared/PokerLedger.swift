import Foundation

// 微乐五十K 牌账状态机 —— PC 版 recognize_fiftyk.py Ledger 类的逐行移植。
// 语义（回放 #12 守恒 0 违规验证版）：
//   新局重置（满26/从0恢复/跳增≥15）→ 同点数去抖 → 花色级纯差分 → 基数夹逼
//   四家分账：按检出位置归属，各家独立 3 帧吸收窗 + 差分。
//
// 关键不变量（勿改，均为 PC 回放踩坑结论）：
//   1. prev_eff 必须基于当前帧之前的窗口（gained 先算、hist 后 append）
//   2. 花色级差分天然免疫换轮重复，不加换轮 skip/clear
//   3. 新局触发帧 skip 入账且 hist 归零
//   4. 夹逼保险丝：JK cap=4、其余 cap=2
public struct PokerLedger {
    public struct Config {
        /// 中央出牌区四家分区阈值（PC 1162x697 坐标系实测值；
        /// iPhone 版需在阶段 2 用真机样本重新标定）
        public var seatTopY = 160.0     // y < seatTopY → 对家
        public var seatBottomY = 240.0  // y >= seatBottomY → 我
        public var seatMidX = 500.0     // 中带 x < seatMidX → 上家，否则下家
        public var handAccept = 0.60    // 手牌分类阈值
        public var ctrAccept = 0.75     // 中央区计数阈值
        public var histFrames = 3       // 多帧吸收窗

        public init() {}
    }

    public struct SeatDisp: Equatable {
        public var name: String
        public var left: Int
        public var cards: String
    }

    public struct FrameResult {
        public var handSuit: Counter
        public var handStar: Counter
        public var gained: Counter
        public var gainedStar: Counter
        public var newGame: Bool
    }

    public var config = Config()

    public private(set) var played = Counter()        // 累计出牌（花色确定）
    public private(set) var playedStar = Counter()    // 累计星标牌（只按牌点）
    private var centerHist: [Counter] = []            // 近 N 帧中央计数，逐类取最大吸收漏检闪烁
    private var starHist: [Counter] = []
    private var prevCenterRanks = Set<String>()       // 上一帧中央检出牌点：同点数确认去抖
    public private(set) var handPrevTotal = 0
    public private(set) var curSeen = Counter()       // 当前已见（手牌+累计出牌），每帧刷新
    public private(set) var curStar = Counter()
    public private(set) var lastGame = (suit: Counter(), star: Counter())  // 新局重置前的上一局末账
    public private(set) var playedSeat = [Counter(), Counter(), Counter(), Counter()]
    private var lastSeat = [Counter(), Counter(), Counter(), Counter()]
    private var seatHist: [[Counter]] = [[], [], [], []]
    public private(set) var seatDisp: [SeatDisp] = [] // [(方位, 剩余, 最近出牌串)]

    public static let seatNames = ["对", "上", "下", "我"]

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func reset() {
        self = PokerLedger(config: config)
    }

    /// 中央出牌区四家分区（PC 实测坐标；iPhone 阶段 2 标定后改 Config）
    func seatOf(x: Double, y: Double) -> Int {
        if y < config.seatTopY { return 0 }           // 对家
        if y >= config.seatBottomY { return 3 }       // 我
        return x < config.seatMidX ? 1 : 2            // 上家 / 下家
    }

    /// 检出 → (花色计数, 星标计数)：星标/伙章牌花色不可判，只计牌点。
    /// JK 排除星标——JOKER 牌面中央图案含大片橙色像素，星标检测必误触发
    static func multiset(_ dets: [CardDetection], accept: Double) -> (suit: Counter, star: Counter) {
        var suit = Counter(), star = Counter()
        for d in dets where d.score >= accept {
            if d.cls == "JK" || !d.star { suit.add(d.cls) }
            if d.star && d.cls != "JK" { star.add(CardDefs.rankOf(d.cls)) }
        }
        return (suit, star)
    }

    /// 单帧检出 → 去抖 → 新局检测 → 差分入账 → 四家分账
    public mutating func processFrame(handDets: [CardDetection], centerDets: [CardDetection]) -> FrameResult {
        let (hs, ht) = PokerLedger.multiset(handDets, accept: config.handAccept)
        let raw = centerDets
        // 去抖：中央检出须在上一帧原始检出中有同点数者才入账（不限位置——
        // 张数变化使整套牌平移 30-40px，位置约束会错位全滤）。首帧放行
        let confirmed: [CardDetection]
        if prevCenterRanks.isEmpty {
            confirmed = raw
        } else {
            confirmed = raw.filter { prevCenterRanks.contains(CardDefs.rankOf($0.cls)) }
        }
        prevCenterRanks = Set(raw.map { CardDefs.rankOf($0.cls) })

        let (cs, ct) = PokerLedger.multiset(confirmed, accept: config.ctrAccept)
        let handTotal = hs.total + ht.total

        // 新一局检测：满 26 张（局中重发）、手牌从 0 恢复增长（发牌动画期
        // 手牌渐增，永远达不到 26 触发条件 → 旧账叠加超基数）、或手牌大幅
        // 增长（五十K 无摸牌，局中手牌只减不增；8→25 跳增 = 新局）
        var newGame = false
        let full = handTotal >= 26 && handPrevTotal > 0 && handPrevTotal < 26
        let resumed = handTotal > 0 && handPrevTotal == 0 && (!played.isEmpty || !centerHist.isEmpty)
        let grew = handTotal >= 15 && handPrevTotal < 15 && handTotal > handPrevTotal
        if full || resumed || grew {
            newGame = true
            lastGame = (curSeen, curStar)
            played = Counter()
            playedStar = Counter()
            centerHist.removeAll()
            starHist.removeAll()
            playedSeat = [Counter(), Counter(), Counter(), Counter()]
            lastSeat = [Counter(), Counter(), Counter(), Counter()]
        }
        handPrevTotal = handTotal

        // prev_eff 基于当前帧之前的窗口（含当前帧会使 gained 恒空）
        var prevEff = Counter()
        for h in centerHist { prevEff |= h }
        var prevStarEff = Counter()
        for h in starHist { prevStarEff |= h }

        var gained = Counter()
        var gainedStar = Counter()
        var skipHist = false
        if newGame {
            // 新局首帧桌面混杂上局残留与发牌动画，不入账不入基准
            skipHist = true
        } else {
            // 花色级差分天然免疫换轮重复：同花色同类牌全局唯一，收走动画
            // 残留/未收走旧牌的键已计过（差分自动 0），只有真新牌是新键入账。
            for (k, v) in cs.d where v > prevEff.get(k) {
                var g = v - prevEff.get(k)
                // 基数夹逼保险丝：王是大牌，桌面停留可超 hist 窗口，检出
                // 闪烁致键消失→重现时差分再入；同键超基数必为重复误检
                let cap = CardDefs.base(k)
                let room = max(0, cap - played.get(k))
                if g > room { g = room }
                if g > 0 { gained.d[k] = g }
            }
            for (k, v) in ct.d where v > prevStarEff.get(k) {
                let g = v - prevStarEff.get(k)
                if g > 0 { gainedStar.d[k] = g }
            }
        }
        played += gained
        playedStar += gainedStar
        centerHist.append(skipHist ? Counter() : cs)
        starHist.append(skipHist ? Counter() : ct)
        if centerHist.count > config.histFrames {
            centerHist.removeFirst()
            starHist.removeFirst()
        }
        curSeen = hs + played
        curStar = ht + playedStar

        // 四家分账：按检出位置归属，花色级差分（各家桌面基准独立）。
        // 新局帧桌面牌写入基准但不入账（与全局路径语义对齐）
        seatDisp = []
        var bySeat: [[CardDetection]] = [[], [], [], []]
        for d in confirmed where d.score >= config.ctrAccept {
            bySeat[seatOf(x: Double(d.x), y: Double(d.y))].append(d)
        }
        for si in 0..<4 {
            var cur = Counter()
            for d in bySeat[si] where d.cls == "JK" || !d.star {
                cur.add(d.cls)
            }
            if newGame {
                seatHist[si] = [cur]
                lastSeat[si] = cur
                continue
            }
            // N 帧窗口逐类最大值吸收闪烁，再差分
            seatHist[si].append(cur)
            if seatHist[si].count > config.histFrames {
                seatHist[si].removeFirst()
            }
            var merged = Counter()
            for h in seatHist[si] { merged |= h }
            var g = Counter()
            for (k, v) in merged.d where v > lastSeat[si].get(k) {
                g.d[k] = v - lastSeat[si].get(k)
            }
            lastSeat[si] = merged
            playedSeat[si] += g
            let left = max(0, 27 - playedSeat[si].total)
            let cards = PokerLedger.flowString(g)
            seatDisp.append(SeatDisp(name: PokerLedger.seatNames[si], left: left, cards: cards))
        }
        return FrameResult(handSuit: hs, handStar: ht, gained: gained,
                           gainedStar: gainedStar, newGame: newGame)
    }

    /// 当前已见 = 手牌快照 + 累计出牌
    public func seen(handSuit: Counter, handStar: Counter) -> (suit: Counter, star: Counter) {
        (handSuit + played, handStar + playedStar)
    }

    /// 主条各牌点剩余：王 = 4 − 已见王 − 王星标；其余 = 8 − 4花色已见 − 星标
    public func mainBar(seen: Counter, star: Counter) -> [String: Int] {
        var out: [String: Int] = [:]
        for r in CardDefs.ranks {
            if r == "JK" {
                out[r] = max(0, 4 - seen.get("JK") - star.get("JK"))
            } else {
                let suitSeen = CardDefs.suits.reduce(0) { $0 + seen.get(r + $1) }
                out[r] = max(0, 8 - suitSeen - star.get(r))
            }
        }
        return out
    }

    /// 出牌流水紧凑串：按牌点升序，王→W、10→0
    static func flowString(_ c: Counter) -> String {
        c.d.sorted { CardDefs.sortKey($0.key) < CardDefs.sortKey($1.key) }
            .map { String(repeating: CardDefs.compact($0.key), count: $0.value) }
            .joined()
    }
}
