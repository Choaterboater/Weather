import Foundation
import CoreLocation

/// Represents a USGS water monitoring site and its latest flow/gage data.
struct WaterSite: Identifiable, Equatable {
    let id: String
    let name: String
    let location: CLLocation
    var distanceMiles: Double?
    
    // Most recent readings
    var flowCFS: Double?       // Discharge, cubic feet per second
    var gageHeightFeet: Double? // Gage height, feet
    var temperatureF: Double?   // Water temperature, Fahrenheit
    
    // Status text based on flow percentiles (if available)
    var flowStatus: String?
}

@MainActor
@Observable
final class USGSWaterClient {
    enum Status: Equatable {
        case idle
        case working
        case ready([WaterSite])
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// Fetches real-time surface water data within a radius of the location.
    /// Uses the USGS Water Services instantaneous values (iv) REST API.
    func loadSites(near location: CLLocation, radiusMiles: Double = 15.0) async {
        status = .working
        
        let urlString = buildUSGSQueryURL(location: location, radiusMiles: radiusMiles)
        guard let url = URL(string: urlString) else {
            status = .failed("Invalid query URL")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                status = .failed("Failed to connect to USGS Water Services.")
                return
            }
            
            // The USGS JSON format is a complex time-series response.
            let usgsResponse = try JSONDecoder().decode(USGSIvResponse.self, from: data)
            let sites = parseUSGSResponse(usgsResponse, center: location)
            
            status = .ready(sites.sorted { ($0.distanceMiles ?? 0) < ($1.distanceMiles ?? 0) })
        } catch {
            status = .failed("USGS Data unavailable: \(error.localizedDescription)")
        }
    }
    
    private func buildUSGSQueryURL(location: CLLocation, radiusMiles: Double) -> String {
        // Parameter codes:
        // 00060 = Discharge, cubic feet per second (CFS)
        // 00065 = Gage height, feet
        // 00010 = Temperature, water, degrees Celsius
        let bBoxStr = boundingBox(center: location.coordinate, radiusMiles: radiusMiles)
        return "https://waterservices.usgs.gov/nwis/iv/?format=json&bBox=\(bBoxStr)&parameterCd=00060,00065,00010&siteStatus=active"
    }
    
    private func boundingBox(center: CLLocationCoordinate2D, radiusMiles: Double) -> String {
        // Roughly 1 degree of latitude is ~69 miles
        let deltaLat = radiusMiles / 69.0
        // Longitude distance varies by latitude
        let deltaLon = radiusMiles / (69.0 * cos(center.latitude * .pi / 180.0))
        
        let minLon = center.longitude - deltaLon
        let minLat = center.latitude - deltaLat
        let maxLon = center.longitude + deltaLon
        let maxLat = center.latitude + deltaLat
        
        // Format: west,south,east,north
        return String(format: "%.4f,%.4f,%.4f,%.4f", minLon, minLat, maxLon, maxLat)
    }
    
    private func parseUSGSResponse(_ response: USGSIvResponse, center: CLLocation) -> [WaterSite] {
        var siteMap: [String: WaterSite] = [:]
        
        for timeSeries in response.value.timeSeries {
            guard let siteInfo = timeSeries.sourceInfo,
                  let locInfo = siteInfo.geoLocation?.geogLocation else { continue }
            
            let siteCode = siteInfo.siteCode.first?.value ?? "unknown"
            let siteName = siteInfo.siteName.capitalized
            
            if siteMap[siteCode] == nil {
                let loc = CLLocation(latitude: locInfo.latitude, longitude: locInfo.longitude)
                siteMap[siteCode] = WaterSite(
                    id: siteCode,
                    name: siteName,
                    location: loc,
                    distanceMiles: center.distance(from: loc) / 1609.34
                )
            }
            
            // Extract the most recent value. USGS uses -999999 as a "no data"
            // sentinel for offline sensors — never treat it as a real reading.
            guard let latestValueStr = timeSeries.values.last?.value.last?.value,
                  let latestValue = Double(latestValueStr),
                  latestValue > -999998 else { continue }
            
            let paramCode = timeSeries.variable.variableCode.first?.value
            
            if paramCode == "00060" { // CFS
                siteMap[siteCode]?.flowCFS = latestValue
            } else if paramCode == "00065" { // Gage Height
                siteMap[siteCode]?.gageHeightFeet = latestValue
            } else if paramCode == "00010" { // Celsius Water Temp
                // Guard against physically impossible water temps (bad sensors).
                guard latestValue > -5, latestValue < 45 else { continue }
                let tempF = (latestValue * 9.0/5.0) + 32.0
                siteMap[siteCode]?.temperatureF = tempF
            }
        }
        
        // Only return sites that have at least some usable fishing data (flow or height or temp)
        return siteMap.values.filter { $0.flowCFS != nil || $0.gageHeightFeet != nil || $0.temperatureF != nil }
    }
    
    // MARK: - USGS JSON Decoding Structures
    
    struct USGSIvResponse: Decodable {
        let value: TimeSeriesData
    }
    
    struct TimeSeriesData: Decodable {
        let timeSeries: [TimeSeries]
    }
    
    struct TimeSeries: Decodable {
        let sourceInfo: SourceInfo?
        let variable: Variable
        let values: [ValuesArray]
    }
    
    struct SourceInfo: Decodable {
        let siteName: String
        let siteCode: [SiteCode]
        let geoLocation: GeoLocation?
    }
    
    struct SiteCode: Decodable {
        let value: String
    }
    
    struct GeoLocation: Decodable {
        let geogLocation: GeogLocationData?
    }
    
    struct GeogLocationData: Decodable {
        let latitude: Double
        let longitude: Double
    }
    
    struct Variable: Decodable {
        let variableCode: [VariableCode]
    }
    
    struct VariableCode: Decodable {
        let value: String
    }
    
    struct ValuesArray: Decodable {
        let value: [DataValue]
    }
    
    struct DataValue: Decodable {
        let value: String
        let dateTime: String
    }
}
