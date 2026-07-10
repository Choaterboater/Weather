import SwiftUI
import CoreLocation

/// Displays real-time water conditions (River flow, gage height, temp) from the USGS.
struct WaterConditionsCard: View {
    let location: CLLocation
    @State private var client = USGSWaterClient()
    @Environment(SpotStore.self) private var spots
    
    // Check if the current spot is definitely saltwater. If so, river gauges might be irrelevant.
    private var isSaltwater: Bool {
        spots.selectedSpot?.waterType == .saltwater
    }
    
    var body: some View {
        // Only show water/river conditions if we aren't explicitly at a saltwater spot
        if !isSaltwater {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Water Conditions", systemImage: "water.waves")
                
                GlassCard {
                    switch client.status {
                    case .idle, .working:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Checking local river gauges…")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Gage data unavailable", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Text(message)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                        
                    case .ready(let sites):
                        if sites.isEmpty {
                            Text("No USGS monitoring stations within 15 miles.")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(sites.prefix(3)) { site in
                                    USGSSiteRow(site: site)
                                    if site.id != sites.prefix(3).last?.id {
                                        Divider().opacity(0.5)
                                    }
                                }
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    Text("Real-time data from USGS Water Services")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    Spacer()
                                }
                                .foregroundStyle(Ink.chartDim)
                                .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .task(id: location.coordinate.latitude) {
                await client.loadSites(near: location)
            }
        }
    }
}

private struct USGSSiteRow: View {
    let site: WaterSite
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(site.name.replacingOccurrences(of: " AT ", with: " \nAT "))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
                    .lineLimit(2)
                Spacer()
                if let distance = site.distanceMiles {
                    Text("\(Int(distance)) mi")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            
            HStack(spacing: 16) {
                if let cfs = site.flowCFS {
                    MetricFact(label: "Flow (CFS)", value: "\(Int(cfs))", icon: "arrow.down.right.and.arrow.up.left")
                }
                
                if let height = site.gageHeightFeet {
                    MetricFact(label: "Gage (Ft)", value: String(format: "%.1f", height), icon: "ruler")
                }
                
                if let temp = site.temperatureF {
                    MetricFact(label: "Water Temp", value: "\(Int(temp.rounded()))°", icon: "thermometer.water")
                }
            }
        }
    }
}

private struct MetricFact: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Ink.chartDim)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.chartDim)
            }
        }
    }
}
