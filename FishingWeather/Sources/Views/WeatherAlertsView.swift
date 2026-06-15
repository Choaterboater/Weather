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
                            .font(.subheadline.weight(.semibold))
                        Text(alert.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Details", destination: alert.detailsURL)
                            .font(.caption.weight(.medium))
                    }
                }
                .tint(.orange)
            }
        }
    }
}
