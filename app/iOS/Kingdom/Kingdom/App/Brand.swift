import SwiftUI
import UIKit

enum Brand {
    static let charcoal = Color(hex: "#1B1B1B")
    static let forest = Color(hex: "#49684A")
    static let clay = Color(hex: "#B3522E")
    static let sand = Color(hex: "#EADCC8")
    static let mist = Color(hex: "#F6F5EF")

    static let fontName = "PlusJakartaSans-Regular"
    static let italicFontName = "PlusJakartaSans-Italic"

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(fontName, size: size).weight(weight)
    }

    static func italicFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(italicFontName, size: size).weight(weight)
    }

    /// UIFont at a specific `wght` axis value for the variable Plus Jakarta Sans font.
    static func uiFont(size: CGFloat, weight: CGFloat = 600) -> UIFont {
        guard let base = UIFont(name: fontName, size: size) else {
            return .systemFont(ofSize: size, weight: .semibold)
        }
        let wghtAxis = 0x7767_6874 // 'wght'
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxis: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
