import Foundation

/// Shared, locale-independent clock formatting for capture and playback UI.
public enum STTSTimeFormat {
    public static func clockString(ms value: Int) -> String {
        let totalSeconds = max(0, value / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
