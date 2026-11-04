import AVFoundation
import Observation

/// Whether headphones are connected. Without them the microphone also hears the music the app
/// plays through the speaker, and instruments get mixed up with the singer's voice.
@Observable
final class Headphones {
    static let shared = Headphones()

    private(set) var connected = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let ports: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio,
    ]

    private init() {
        check()
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        let now = AVAudioSession.sharedInstance().currentRoute.outputs.contains { Headphones.ports.contains($0.portType) }
        if now != connected { connected = now }
    }
}
