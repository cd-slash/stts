import SwiftUI

/// Design-system tokens for STTS.
///
/// `docs/design/README.md` is normative: colour and type values live only in
/// this file, and views reference the tokens by name. There is one dark
/// appearance; there is no light variant.
///
/// Type roles map onto the system text styles so Dynamic Type keeps working.
/// At the default size the styles match the scale exactly: display
/// `largeTitle` (34), title `title2` (22), body `body` (17), caption
/// `footnote` (13), micro `caption2` (11).

// MARK: Colour

extension Color {
    private init(token value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `void` — app background, true black.
    static let sttsVoid = Color(token: 0x000000)
    /// `surface` — coordinator bubble, list row.
    static let sttsSurface = Color(token: 0x141417)
    /// `surfaceRaised` — composer, text fields, selected row.
    static let sttsSurfaceRaised = Color(token: 0x1C1C21)
    /// `hairline` — decorative separators and grouping.
    static let sttsHairline = Color(token: 0x33333A)
    /// `outline` — meaningful boundaries and control edges.
    static let sttsOutline = Color(token: 0x5F5F68)
    /// `ink` — primary text.
    static let sttsInk = Color(token: 0xF4F4F6)
    /// `inkMuted` — metadata, secondary text.
    static let sttsInkMuted = Color(token: 0x8B8B94)
    /// `inkFaint` — disabled text.
    static let sttsInkFaint = Color(token: 0x5A5A63)
    /// `live` — recording and listening only.
    static let sttsLive = Color(token: 0xF0A868)
    /// `alert` — failure and destructive actions.
    static let sttsAlert = Color(token: 0xFF6B5E)
}

// MARK: Type

extension Font {
    /// Display — the live state and the empty state only.
    static let sttsDisplay = Font.system(.largeTitle).weight(.heavy)
    /// Title.
    static let sttsTitle = Font.system(.title2).weight(.semibold)
    /// Body.
    static let sttsBody = Font.system(.body)
    /// Caption — metadata and secondary text.
    static let sttsCaption = Font.system(.footnote)
    /// Micro — dense rows only.
    static let sttsMicro = Font.system(.caption2).weight(.medium)

    /// Body with tabular figures — elapsed counters.
    static let sttsBodyTabular = Font.sttsBody.monospacedDigit()
    /// Caption with tabular figures — timestamps and durations.
    static let sttsCaptionTabular = Font.sttsCaption.monospacedDigit()
    /// Micro with tabular figures — dense numeric rows.
    static let sttsMicroTabular = Font.sttsMicro.monospacedDigit()
}

// MARK: Tracking

/// Letter tracking for the type roles, in points.
enum SttsTracking {
    static let display: CGFloat = -0.4
    static let title: CGFloat = -0.2
}

extension Text {
    /// Applies the display role — the live state and the empty state only.
    func sttsDisplay() -> Text {
        font(.sttsDisplay).tracking(SttsTracking.display)
    }

    /// Applies the title role.
    func sttsTitle() -> Text {
        font(.sttsTitle).tracking(SttsTracking.title)
    }
}
