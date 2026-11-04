import AVFoundation
import UIKit

/// The shared audio session: listen and play at the same time, loudspeaker by default and
/// Bluetooth headphones allowed for playback.
enum AudioSession {
    private static var configured = false

    static func activate() {
        let session = AVAudioSession.sharedInstance()
        if !configured {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try? session.setPreferredIOBufferDuration(0.01)
            configured = true
        }
        try? session.setActive(true)
    }

    /// Time between rendering a sample and hearing it, in milliseconds.
    static var outputLatencyMs: Double {
        let session = AVAudioSession.sharedInstance()
        return (session.outputLatency + session.ioBufferDuration) * 1000
    }
}

/// Monotonic host clock in nanoseconds (the same clock as audio time stamps).
enum HostClock {
    private static let factor: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    static func ns(_ hostTime: UInt64) -> Int64 { Int64(Double(hostTime) * factor) }

    static func nowNs() -> Int64 { ns(mach_absolute_time()) }

    static func nowMs() -> Double { Double(nowNs()) / 1e6 }
}

/// Calls `onFrame` once per display refresh while started.
final class DisplayLink {
    private final class Proxy: NSObject {
        weak var owner: DisplayLink?

        @objc func tick(_ link: CADisplayLink) { owner?.onFrame(link.timestamp) }
    }

    private var link: CADisplayLink?
    private let onFrame: (CFTimeInterval) -> Void

    init(_ onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
    }

    var running: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        let proxy = Proxy()
        proxy.owner = self
        let l = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit { link?.invalidate() }
}
