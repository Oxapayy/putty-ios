import UIKit
import SwiftTerm

struct TerminalPalette {
    let ansi: [(UInt8, UInt8, UInt8)]
    let foreground: (UInt8, UInt8, UInt8)
    let background: (UInt8, UInt8, UInt8)
    let cursor: (UInt8, UInt8, UInt8)

    var swiftTermColors: [SwiftTerm.Color] {
        ansi.map { SwiftTerm.Color(red: UInt16($0.0) * 257, green: UInt16($0.1) * 257, blue: UInt16($0.2) * 257) }
    }

    static func ui(_ c: (UInt8, UInt8, UInt8)) -> UIColor {
        UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
    }

    /// PuTTY's built-in default colours.
    private static let puttyANSI: [(UInt8, UInt8, UInt8)] = [
        (0, 0, 0), (187, 0, 0), (0, 187, 0), (187, 187, 0), (0, 0, 187), (187, 0, 187), (0, 187, 187), (187, 187, 187),
        (85, 85, 85), (255, 85, 85), (85, 255, 85), (255, 255, 85), (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255),
    ]

    static func scheme(_ s: ColourScheme) -> TerminalPalette {
        switch s {
        case .puttyDefault:
            return TerminalPalette(ansi: puttyANSI, foreground: (187, 187, 187), background: (0, 0, 0), cursor: (0, 255, 0))
        case .xterm:
            return TerminalPalette(ansi: [
                (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
                (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
            ], foreground: (229, 229, 229), background: (0, 0, 0), cursor: (229, 229, 229))
        case .blackOnWhite:
            return TerminalPalette(ansi: puttyANSI, foreground: (0, 0, 0), background: (255, 255, 255), cursor: (0, 0, 0))
        case .greenOnBlack:
            return TerminalPalette(ansi: puttyANSI, foreground: (51, 255, 51), background: (0, 0, 0), cursor: (51, 255, 51))
        case .solarizedDark:
            return TerminalPalette(ansi: [
                (7, 54, 66), (220, 50, 47), (133, 153, 0), (181, 137, 0), (38, 139, 210), (211, 54, 130), (42, 161, 152), (238, 232, 213),
                (0, 43, 54), (203, 75, 22), (88, 110, 117), (101, 123, 131), (131, 148, 150), (108, 113, 196), (147, 161, 161), (253, 246, 227),
            ], foreground: (131, 148, 150), background: (0, 43, 54), cursor: (147, 161, 161))
        }
    }
}

enum TerminalFonts {
    static func set(on view: TerminalView, font: TermFont, size: Double) {
        let s = CGFloat(size)
        switch font {
        case .courierNew:
            view.setFonts(normal: named("CourierNewPSMT", s), bold: named("CourierNewPS-BoldMT", s),
                          italic: named("CourierNewPS-ItalicMT", s), boldItalic: named("CourierNewPS-BoldItalicMT", s))
        case .menlo:
            view.setFonts(normal: named("Menlo-Regular", s), bold: named("Menlo-Bold", s),
                          italic: named("Menlo-Italic", s), boldItalic: named("Menlo-BoldItalic", s))
        case .systemMono:
            let regular = UIFont.monospacedSystemFont(ofSize: s, weight: .regular)
            let bold = UIFont.monospacedSystemFont(ofSize: s, weight: .bold)
            view.setFonts(normal: regular, bold: bold, italic: italic(regular), boldItalic: italic(bold))
        }
    }

    static func preview(_ font: TermFont, size: Double) -> UIFont {
        switch font {
        case .courierNew: return named("CourierNewPSMT", CGFloat(size))
        case .menlo: return named("Menlo-Regular", CGFloat(size))
        case .systemMono: return .monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        }
    }

    private static func named(_ name: String, _ size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func italic(_ f: UIFont) -> UIFont {
        guard let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.traitItalic)) else { return f }
        return UIFont(descriptor: d, size: f.pointSize)
    }
}
