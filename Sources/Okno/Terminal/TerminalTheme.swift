import AppKit
import SwiftTerm

/// Terminal colours for light and dark appearance: the system text colours, and 16 ANSI colours
/// that stay readable on them.
struct TerminalTheme {
    let foreground: NSColor
    let background: NSColor
    let caret: NSColor
    let selection: NSColor
    let ansi: [SwiftTerm.Color]

    /// The theme for `appearance`, with every system colour resolved for it.
    static func resolved(for appearance: NSAppearance) -> TerminalTheme {
        let dark = isDark(appearance)
        var theme: TerminalTheme!
        appearance.performAsCurrentDrawingAppearance {
            theme = TerminalTheme(
                foreground: srgb(.textColor),
                background: srgb(.textBackgroundColor),
                caret: srgb(dark ? NSColor(white: 0.72, alpha: 1) : NSColor(white: 0.45, alpha: 1)),
                selection: srgb(.selectedTextBackgroundColor),
                ansi: (dark ? darkANSI : lightANSI).map(color))
        }
        return theme
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Black, red, green, yellow, blue, magenta, cyan, white, then the bright eight.
    /// The six colours are mid-tones: as text they read on the background (light 4.4–5.3:1,
    /// dark 4.0–5.4:1), and black or white text reads on them (prompt themes draw segments
    /// that way). White is light gray, as in Terminal.app, so it reads on coloured segments.
    private static let lightANSI: [UInt32] = [
        0x000000, 0xC8312B, 0x2E8A30, 0x947500, 0x3A70CC, 0xB13BB0, 0x10818B, 0xD8D8DC,
        0x8E8E93, 0xE0473F, 0x36A33A, 0xB08C00, 0x4D88E8, 0xC855C7, 0x1A9BA6, 0xF2F2F5,
    ]
    private static let darkANSI: [UInt32] = [
        0x000000, 0xE0453D, 0x36A03C, 0xB38F12, 0x4283E8, 0xC155C9, 0x1D9EAA, 0xC7C7CC,
        0x808086, 0xFF8F87, 0x6BD979, 0xEDC452, 0x8CC1FF, 0xE3A6F0, 0x70DCE6, 0xF5F5F7,
    ]

    private static func color(_ rgb: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(red8: UInt16((rgb >> 16) & 0xFF),
                        green8: UInt16((rgb >> 8) & 0xFF),
                        blue8: UInt16(rgb & 0xFF))
    }

    private static func srgb(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
