import SwiftUI

/// The Home/Lock Screen widget's face: a glanceable bite reading for the active
/// spot. Pure SwiftUI over a `WidgetSnapshot`, so it renders in the widget
/// extension and in-app previews alike. The detailed Bite Gauge stays the
/// in-app hero; the widget distills it to score, band, and the next window.
struct BiteWidgetView: View {
    let snapshot: WidgetSnapshot

    private var band: Color { Ink.band(for: snapshot.score) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("BITECAST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Ink.brass)
                Spacer()
                Image(systemName: "fish.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Ink.brass)
            }

            Spacer(minLength: 6)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(snapshot.score)")
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .foregroundStyle(band)
                Text(snapshot.summary)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(band)
                    .padding(.bottom, 7)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hullLine)
                    Capsule()
                        .fill(band)
                        .frame(width: max(4, geo.size.width * CGFloat(snapshot.score) / 100))
                }
            }
            .frame(height: 5)
            .padding(.top, 2)

            Spacer(minLength: 6)

            Text(snapshot.locationName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
            if let next = snapshot.nextWindowLabel {
                Text(next)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Ink.abyss)
    }
}
