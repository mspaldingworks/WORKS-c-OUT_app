import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The WORKS(c)OUT palette, taken from the logo: a violet → cobalt → teal → mint
/// sweep behind a white (c), with the wordmark set in deep navy ink.
///
/// The raw logo colours are tuned for a big tile, not for small text on white —
/// mint on white is barely legible — so every colour used for text or symbols
/// has a light/dark pair: deeper in light mode, brighter in dark mode, each
/// readable against the system background it sits on.
enum Brand {
    // MARK: Logo colours (fills, gradients, large shapes)

    static let ink = Color(hex: 0x0A1F44)
    static let violet = Color(hex: 0x7B2FC2)
    static let cobalt = Color(hex: 0x1450C0)
    static let teal = Color(hex: 0x0E9DBF)
    static let aqua = Color(hex: 0x3FD9B8)
    static let mint = Color(hex: 0x56E885)

    /// The tile's sweep, bottom-left violet to top-right mint.
    static let gradient = LinearGradient(
        colors: [violet, cobalt, teal, mint],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    // MARK: Interface colours (text, symbols, tints)

    /// App-wide tint: buttons, links, selection, active filter chips.
    static let accent = Color(light: 0x1450C0, dark: 0x4DA8FF)
    /// Something that's going well — a strong match, an approved draft.
    static let positive = Color(light: 0x0B8A5E, dark: 0x56E39A)
    /// Recency: the "posted" stamp on a job card.
    static let fresh = Color(light: 0x0A7FA3, dark: 0x3DD3E0)
    /// Context rather than a warning — skills she'd be learning.
    static let learn = Color(light: 0x6B2FBF, dark: 0xB790FF)
    /// Headings and the wordmark's ink; white-ish in dark mode.
    static let heading = Color(light: 0x0A1F44, dark: 0xF4F7FF)
}

/// The logo tile — rounded, transparent corners — for in-app use.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "WorkS(c)out" lettering. The asset has a dark-mode variant with white ink.
struct BrandWordmark: View {
    var height: CGFloat = 22

    var body: some View {
        Image("BrandWordmark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("WORKS(c)OUT")
    }
}

/// A thin strip of the logo gradient, used as a header rule.
struct BrandRule: View {
    var body: some View {
        Brand.gradient
            .frame(height: 3)
            .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif canImport(AppKit)
        self.init(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #endif
    }
}
