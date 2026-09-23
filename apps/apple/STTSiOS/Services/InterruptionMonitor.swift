import AVFoundation
import Foundation

/// Delivers AVAudioSession interruption events (e.g. phone calls) to a
/// main-actor callback. The block-based observer only captures a
/// `@MainActor`-isolated (therefore Sendable) closure, never self.
final class InterruptionMonitor {
    private let observer: NSObjectProtocol

    init(onInterruption: @escaping @MainActor (Bool) -> Void) {
        let handler = onInterruption
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
                return
            }
            let began = AVAudioSession.InterruptionType(rawValue: raw) == .began
            Task { @MainActor in handler(began) }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
    }
}
