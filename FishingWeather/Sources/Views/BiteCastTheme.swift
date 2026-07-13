import SwiftUI

/// Native outdoors design tokens for BiteCast: deep water surfaces, warm
/// chart-paper language, and a restrained brass accent. Measurements may use
/// monospaced digits, while headings and prose use the system rounded face.
enum Ink {
    static let abyss    = Color(red: 0.031, green: 0.075, blue: 0.122) // #08131F ground
    static let hull     = Color(red: 0.071, green: 0.157, blue: 0.231) // #12283B panel
    static let hullLine = Color(red: 0.118, green: 0.231, blue: 0.322) // #1E3B52 hairline
    static let chart    = Color(red: 0.910, green: 0.875, blue: 0.780) // #E8DFC7 warm text
    static let chartDim = Color(red: 0.624, green: 0.690, blue: 0.741) // #9FB0BD muted
    static let brass    = Color(red: 0.878, green: 0.627, blue: 0.235) // #E0A03C accent
    static let bite     = Color(red: 0.247, green: 0.725, blue: 0.541) // #3FB98A go
    static let slack    = Color(red: 0.776, green: 0.314, blue: 0.243) // #C6503E caution
    static let tide     = Color(red: 0.302, green: 0.678, blue: 0.784) // #4DADC8 water
    static let card     = Color(red: 0.078, green: 0.153, blue: 0.216) // calm surface base

    /// Score-band color on the marine palette (bite → brass → slack).
    static func band(for score: Int) -> Color {
        switch score {
        case 65...: bite
        case 40..<65: brass
        default: slack
        }
    }

    /// The app's dark instrument background gradient.
    static var backdrop: some View {
        ZStack {
            abyss
            RadialGradient(colors: [hull.opacity(0.9), abyss],
                           center: .top, startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A compact native section label. Callers keep their natural casing.
    func instrumentLabel(_ color: Color = Ink.chartDim) -> some View {
        self.font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// A raised, quiet surface for grouped content. Glass is reserved for controls.
struct InstrumentPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card.opacity(0.96), in: .rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Ink.hullLine.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}
