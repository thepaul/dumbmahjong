import SwiftUI
import UIKit

/// `@AppStorage` keys for the settings screen.
enum SettingsKey {
    static let showTimer = "showTimer"
    static let dimBlocked = "dimBlocked"
    static let tableColor = "tableColor"
    static let haptics = "haptics"
}

/// Calm table colors behind the board.
enum TableColor: String, CaseIterable, Identifiable {
    case felt, slate, walnut, charcoal

    var id: Self { self }

    var name: String {
        switch self {
        case .felt: "Felt"
        case .slate: "Slate"
        case .walnut: "Walnut"
        case .charcoal: "Charcoal"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .felt: UIColor(red: 0.12, green: 0.36, blue: 0.24, alpha: 1)
        case .slate: UIColor(red: 0.20, green: 0.27, blue: 0.34, alpha: 1)
        case .walnut: UIColor(red: 0.30, green: 0.21, blue: 0.15, alpha: 1)
        case .charcoal: UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

/// Play time as "4:32", or "1:04:32" past an hour.
func formatPlayTime(seconds: Double) -> String {
    let d = Duration.seconds(Int(seconds))
    return seconds >= 3600
        ? d.formatted(.time(pattern: .hourMinuteSecond))
        : d.formatted(.time(pattern: .minuteSecond))
}
