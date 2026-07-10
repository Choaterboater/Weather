import SwiftUI
import WeatherKit

struct WeatherAlertsView: View {
    let alerts: [WeatherAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Alerts", systemImage: "exclamationmark.triangle")
            ForEach(alerts, id: \.detailsURL) { alert in
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.summary)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(alert.source)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                        Link("Details", destination: alert.detailsURL)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .tint(.orange)
            }
        }
    }
}
