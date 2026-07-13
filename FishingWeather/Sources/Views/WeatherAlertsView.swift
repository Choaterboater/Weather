import SwiftUI

struct WeatherAlertsView: View {
    let alerts: [WeatherAlertSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Alerts", systemImage: "exclamationmark.triangle")
            ForEach(alerts) { alert in
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.summary)
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundStyle(Ink.chart)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alert.source)
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(Ink.chartDim)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detailsURL = alert.detailsURL {
                            Link("Official alert details", destination: detailsURL)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Official alert details from \(alert.source)")
                                .accessibilityIdentifier("weather.alert.\(alert.id).details")
                        }
                    }
                }
                .tint(.orange)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(alert.summary), issued by \(alert.source)")
            }
        }
    }
}
