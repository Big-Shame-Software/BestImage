// BSSBrand.swift — Big Shame Software brand tokens (styleguide v1.0).
// Drop into an app target. Use ONLY on brand surfaces (About, splash,
// empty states, onboarding). Working UI uses system colors and text styles.

import SwiftUI

enum BSSBrand {
    // MARK: Core palette (§4)
    static let plumInk        = Color(hex: 0x2A0B1E)
    static let computerBeige  = Color(hex: 0xEAD2A8)
    static let cream          = Color(hex: 0xFFF4DE)
    static let phosphorGreen  = Color(hex: 0x7DFF3A)
    static let crtGreen       = Color(hex: 0x0E2E1C)
    static let hotMagenta     = Color(hex: 0xFF2D6F)
    static let sunsetOrange   = Color(hex: 0xFF7A1F)
    static let sunshineYellow = Color(hex: 0xFFD43B)
    static let aquaCyan       = Color(hex: 0x22C7D9)
    static let dust           = Color(hex: 0x8A7560)

    // Games and Trail extras
    static let prairieGold    = Color(hex: 0xE8B04A)
    static let skyBlue        = Color(hex: 0x6EC6E8)
    static let wagonBrown     = Color(hex: 0x7A4A2A)

    // PLM sub-brand
    static let plmCobalt      = Color(hex: 0x0057C8)
    static let plmCream       = Color(hex: 0xF4EAD6)

    /// Fixed order: magenta, orange, yellow, cyan. Never reorder.
    static let rainbow: [Color] = [hotMagenta, sunsetOrange, sunshineYellow, aquaCyan]

    /// Every named color above with its hex value. The crop color meter uses this to name
    /// a sampled color. Keep it in sync when a color changes.
    static let namedHex: [(name: String, hex: UInt32)] = [
        ("plumInk", 0x2A0B1E),
        ("computerBeige", 0xEAD2A8),
        ("cream", 0xFFF4DE),
        ("phosphorGreen", 0x7DFF3A),
        ("crtGreen", 0x0E2E1C),
        ("hotMagenta", 0xFF2D6F),
        ("sunsetOrange", 0xFF7A1F),
        ("sunshineYellow", 0xFFD43B),
        ("aquaCyan", 0x22C7D9),
        ("dust", 0x8A7560),
        ("prairieGold", 0xE8B04A),
        ("skyBlue", 0x6EC6E8),
        ("wagonBrown", 0x7A4A2A),
        ("plmCobalt", 0x0057C8),
        ("plmCream", 0xF4EAD6),
    ]

    enum Category: String, CaseIterable {
        case libraryUtilities = "Library and Utilities"
        case media = "Media"
        case terminalDeveloper = "Terminal and Developer"
        case gamesTrail = "Games and Trail"
        case educationKids = "Education and Kids"
        case logsMonitoring = "Logs and Monitoring"
        case publisherMeta = "Publisher and Meta"

        var primary: Color {
            switch self {
            case .libraryUtilities: plmCobalt
            case .media: hotMagenta
            case .terminalDeveloper: phosphorGreen
            case .gamesTrail: sunsetOrange
            case .educationKids: sunshineYellow
            case .logsMonitoring: computerBeige
            case .publisherMeta: plumInk
            }
        }

        var secondary: Color {
            switch self {
            case .libraryUtilities: sunshineYellow
            case .media: aquaCyan
            case .terminalDeveloper: crtGreen
            case .gamesTrail: prairieGold
            case .educationKids: aquaCyan
            case .logsMonitoring: phosphorGreen
            case .publisherMeta: hotMagenta
            }
        }

        /// Whether the rainbow stripe belongs on this category's brand surfaces.
        var usesRainbow: Bool { self != .terminalDeveloper }
    }

    /// Warm brand-surface background: Cream/Beige in light, Plum/CRT in dark. Never black.
    static func surface(_ scheme: ColorScheme, category: Category) -> Color {
        switch (scheme, category) {
        case (.dark, .terminalDeveloper), (.dark, .logsMonitoring): crtGreen
        case (.dark, _): plumInk
        case (_, .logsMonitoring): computerBeige
        default: cream
        }
    }
}

/// 6 px four-band rainbow bar for the top of a brand view (§4, §9).
struct BSSRainbowStripe: View {
    var height: CGFloat = 6
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(BSSBrand.rainbow.enumerated()), id: \.offset) { _, c in
                c.frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
