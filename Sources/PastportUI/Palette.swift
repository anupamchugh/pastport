import SwiftUI

/// The 2.0 palette from DESIGN.md: parchment cards, ink text, one teal accent.
/// Each pair of light and dark values meets 4.5:1 for body text (measured in slice 7).
public struct PaletteColor: ShapeStyle {
    let light: Color
    let dark: Color

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.colorScheme == .dark ? dark : light).resolve(in: environment)
    }
}

public enum Palette {
    public static let background = PaletteColor(light: hex(0xF3EFE6), dark: hex(0x15181E))
    public static let card = PaletteColor(light: hex(0xFFFDF8), dark: hex(0x1F232B))
    public static let card2 = PaletteColor(light: hex(0xEBE6D9), dark: hex(0x2A2F38))
    public static let line = PaletteColor(light: hex(0xD8D1BF), dark: hex(0x363C47))
    public static let ink = PaletteColor(light: hex(0x1C2330), dark: hex(0xECE8DF))
    public static let muted = PaletteColor(light: hex(0x5D6573), dark: hex(0xA3AAB6))
    public static let accent = PaletteColor(light: hex(0x0F6B6B), dark: hex(0x5CC0BC))
    public static let onAccent = PaletteColor(light: hex(0xFFFFFF), dark: hex(0x0B1A1A))
    public static let chipText = PaletteColor(light: hex(0x7A5A12), dark: hex(0xE9C97C))
    public static let chipFill = PaletteColor(light: hex(0xF6EAD0), dark: hex(0x3A3122))
    /// Redaction bars: solid ink, so hidden text reads as blacked out in both modes.
    public static let redaction = PaletteColor(light: hex(0x1C2330), dark: hex(0x0A0C10))

    static func hex(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// A mono uppercase source label, such as PHOTO ACTIVITY.
public struct SourceLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(Palette.chipText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Palette.chipFill, in: Capsule())
    }
}

/// A banner with a coloured leading edge, for Face ID errors, offline and "Apple Intelligence is off".
public struct NoticeBanner: View {
    let text: String
    let symbol: String

    public init(_ text: String, symbol: String) { self.text = text; self.symbol = symbol }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text(text).font(.footnote).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(Palette.accent).frame(width: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Card surface shared by the 2.0 screens.
struct PaperCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
    }
}

extension View {
    func paperCard() -> some View { modifier(PaperCard()) }
}
