import SwiftUI

struct ForecastSafetyNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(ForecastSafetyNoticeContent.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text(ForecastSafetyNoticeContent.message)
                    .font(.system(.caption2, design: .rounded))
            }
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(Ink.chartDim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("forecast.safetyNotice")
    }
}

struct ModifiedWeatherDataNotice: View {
    let attribution: WeatherProviderAttribution

    var body: some View {
        if ModifiedWeatherDataNoticeContent.isRequired(for: attribution) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModifiedWeatherDataNoticeContent.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    Text(ModifiedWeatherDataNoticeContent.message)
                        .font(.system(.caption2, design: .rounded))
                }
            } icon: {
                Image(systemName: "function")
            }
            .foregroundStyle(Ink.chartDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("weather.modifiedDataNotice")
        }
    }
}
