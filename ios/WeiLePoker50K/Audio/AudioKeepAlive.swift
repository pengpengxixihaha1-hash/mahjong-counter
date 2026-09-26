import AVFoundation

// PiP 保活：iOS 在 App 退后台后若无活跃音频会话会回收 PiP 窗口。
// 标准做法：playback 类别 + 无声循环音频。
enum AudioKeepAlive {
    private static var player: AVAudioPlayer?

    static func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: silentWav())
        }
        player?.numberOfLoops = -1
        player?.volume = 0.01
        player?.play()
    }

    static func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation])
    }

    /// 运行时生成 2 秒静音 WAV（8000Hz / 16bit / mono）
    private static func silentWav() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wl50k_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8000
        let dataSize = sampleRate * 2 * 2
        var data = Data()
        func u32(_ v: UInt32) { data.append(withUnsafeBytes(of: v.littleEndian) { Data($0) }) }
        func u16(_ v: UInt16) { data.append(withUnsafeBytes(of: v.littleEndian) { Data($0) }) }
        func str(_ s: String) { data.append(s.data(using: .ascii)!) }
        str("RIFF"); u32(UInt32(36 + dataSize)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        try? data.write(to: url)
        return url
    }
}
