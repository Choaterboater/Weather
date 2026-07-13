import SwiftUI
import UIKit

/// Renders provider-supplied branding and the corresponding official legal
/// destination. Apple branding always comes from WeatherKit's combined-mark
/// URLs; BiteCast never recreates or substitutes that artwork.
struct WeatherSourceAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let attribution: WeatherProviderAttribution

    private var presentation: WeatherSourceAttributionPresentation? {
        .make(attribution)
    }

    var body: some View {
        if let presentation {
            VStack(alignment: .leading, spacing: 6) {
                switch attribution.providerKind {
                case .appleWeather:
                    appleAttribution(presentation)
                case .nationalWeatherService:
                    Link(
                        presentation.legalLinkLabel,
                        destination: presentation.legalURL
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("weather.source.nws.link")
                }

                if let legalText = presentation.legalText,
                   !legalText.isEmpty {
                    Text(legalText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Ink.chartDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityIdentifier("weather.source.attribution")
        }
    }

    @ViewBuilder
    private func appleAttribution(
        _ presentation: WeatherSourceAttributionPresentation
    ) -> some View {
        let markData = colorScheme == .dark
            ? presentation.darkMarkData
            : presentation.lightMarkData

        if let markData, let mark = UIImage(data: markData) {
            Link(destination: presentation.legalURL) {
                Image(uiImage: mark)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: 150,
                        minHeight: 20,
                        maxHeight: 24,
                        alignment: .leading
                    )
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(presentation.legalLinkLabel)
            .accessibilityHint("Opens provider legal attribution")
            .accessibilityIdentifier("weather.source.apple.link")
        }
    }
}
