import CoreFoundation
import Foundation

// 双进程共享：Broadcast Extension 写 → 主 App 读（App Group UserDefaults + 容器目录）
// App 以 0.5s 轮询为主（KVS 跨进程有毫秒级延迟，够用），Darwin 通知仅作即时提醒。
public enum IPC {
    public static let suiteName = "group.com.wl50k.poker50k"
    public static let stateKey = "wl50k.state"
    public static let collectKey = "wl50k.collect"   // Bool：样本采集模式开关
    public static let darwinName = "com.wl50k.poker50k.update"
    public static let samplesSubdir = "Samples"
    /// 样本采集上限：约 2fps × 10 分钟，防止磁盘无限增长
    public static let maxSamples = 1200

    public static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    public struct Snapshot: Codable, Equatable {
        public struct Seat: Codable, Equatable {
            public var name: String
            public var left: Int
            public var cards: String

            public init(name: String, left: Int, cards: String) {
                self.name = name
                self.left = left
                self.cards = cards
            }
        }

        public var status: String
        public var collecting: Bool
        public var sampleCount: Int
        public var newGame: Bool
        public var main: [String: Int]      // 点数 → 剩余（"JK"/"2".."3"）
        public var seats: [Seat]            // 对/上/下/我 顺序

        public init(status: String, collecting: Bool, sampleCount: Int,
                    newGame: Bool, main: [String: Int], seats: [Seat]) {
            self.status = status
            self.collecting = collecting
            self.sampleCount = sampleCount
            self.newGame = newGame
            self.main = main
            self.seats = seats
        }

        public static let empty = Snapshot(status: "等待广播", collecting: false,
                                           sampleCount: 0, newGame: false,
                                           main: [:], seats: [])
    }

    // MARK: - 状态读写

    public static func write(_ s: Snapshot) {
        guard let defaults = defaults,
              let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: stateKey)
        notify()
    }

    public static func read() -> Snapshot {
        guard let defaults = defaults,
              let data = defaults.data(forKey: stateKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .empty
        }
        return s
    }

    public static func notify() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotificationCenter(),
            CFNotificationName(darwinName as CFString), nil, nil, true)
    }

    // MARK: - 样本采集开关与目录

    public static var collecting: Bool {
        get { defaults?.object(forKey: collectKey) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: collectKey) }
    }

    public static var containerDir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    public static var samplesDir: URL? {
        guard let base = containerDir else { return nil }
        return base.appendingPathComponent(samplesSubdir, isDirectory: true)
    }

    public static func ensureSamplesDir() -> URL? {
        guard let dir = samplesDir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func sampleFiles() -> [URL] {
        guard let dir = samplesDir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return names.filter { $0.hasPrefix("frame_") && $0.hasSuffix(".jpg") }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }

    /// 导出准备：把 App Group 容器里的样本复制到主 App 的 Documents/样本
    /// （iTunes / Apple Devices「文件共享」只能看到 Documents），返回目标目录。
    public static func copySamplesToDocuments() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs, let src = samplesDir else { return nil }
        let dst = docs.appendingPathComponent("样本", isDirectory: true)
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
            for f in sampleFiles() {
                try FileManager.default.copyItem(at: f, to: dst.appendingPathComponent(f.lastPathComponent))
            }
            return dst
        } catch {
            return nil
        }
    }
}
