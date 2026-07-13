import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("OpenStreetMap parsing")
struct OpenStreetMapClientTests {
    @Test("Node and way IDs with the same number remain distinct")
    func nodeAndWayIDsAreNamespaced() throws {
        let data = Data(
            """
            {
              "elements": [
                {
                  "type": "node",
                  "id": 42,
                  "lat": 27.7600,
                  "lon": -82.6400,
                  "tags": { "amenity": "boat_ramp", "name": "Node Ramp" }
                },
                {
                  "type": "way",
                  "id": 42,
                  "center": { "lat": 27.7700, "lon": -82.6500 },
                  "tags": { "amenity": "boat_ramp", "name": "Way Ramp" }
                }
              ]
            }
            """.utf8
        )

        let pins = try OpenStreetMapClient.pins(from: data)

        #expect(pins.count == 2)
        #expect(Set(pins.map(\.id)).count == 2)
        #expect(Set(pins.map(\.id)) == ["node/42", "way/42"])
    }

    @Test("Every external request uses the contactable BiteCast identity")
    func externalRequestIdentity() throws {
        #expect(AppIdentity.canonicalContactURL.absoluteString == "https://github.com/Choaterboater/Weather")
        #expect(
            AppIdentity.userAgent(version: "1.2.3")
                == "BiteCast/1.2.3 (+https://github.com/Choaterboater/Weather)"
        )
        #expect(
            AppIdentity.userAgent(version: "1.2.3-beta.1")
                == "BiteCast/1.2.3-beta.1 (+https://github.com/Choaterboater/Weather)"
        )
        #expect(
            AppIdentity.userAgent(version: "not a version")
                == "BiteCast/0.1.0 (+https://github.com/Choaterboater/Weather)"
        )
        #expect(!AppIdentity.userAgent(version: "1.2.3").contains("secure-ssid"))

        let location = CLLocation(latitude: 30.2938, longitude: -86.0049)
        let osmRequest = OpenStreetMapClient.request(near: location, radiusMiles: 25)
        #expect(osmRequest.value(forHTTPHeaderField: "User-Agent") == AppIdentity.userAgent)
        #expect(String(decoding: try #require(osmRequest.httpBody), as: UTF8.self).contains("30.29,-86.00"))

        let iNaturalistRequest = try INaturalistClient.request(
            taxonName: "Micropterus salmoides",
            near: location,
            radiusMiles: 50,
            now: Date(timeIntervalSince1970: 1_720_000_000)
        )
        #expect(iNaturalistRequest.value(forHTTPHeaderField: "User-Agent") == AppIdentity.userAgent)
        let requestURL = try #require(iNaturalistRequest.url)
        let components = try #require(
            URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        )
        #expect(components.queryItems?.first(where: { $0.name == "lat" })?.value == "30.29")
        #expect(components.queryItems?.first(where: { $0.name == "lng" })?.value == "-86.00")
        #expect(
            components.queryItems?.first(where: { $0.name == "photo_license" })?.value
                == "cc0,cc-by,pd"
        )

        let imageRequest = INaturalistClient.imageRequest(
            for: URL(string: "https://inaturalist-open-data.s3.amazonaws.com/photos/1/square.jpg")!
        )
        #expect(imageRequest.value(forHTTPHeaderField: "User-Agent") == AppIdentity.userAgent)
        #expect(imageRequest.value(forHTTPHeaderField: "Accept") == "image/*")
    }

    @Test("Coordinate minimization rounds at privacy boundaries")
    func coordinateMinimization() {
        let location = CLLocation(latitude: 30.2938, longitude: -86.0049)

        #expect(
            ExternalRequestPrivacy.coordinateString(location, decimalPlaces: 3)
                == "30.294,-86.005"
        )
        #expect(
            ExternalRequestPrivacy.coordinateString(location, decimalPlaces: 2)
                == "30.29,-86.00"
        )
    }

    @Test("OpenStreetMap attribution has the required accessible destination")
    func openStreetMapAttributionDestination() {
        #expect(
            ExternalServiceAttribution.openStreetMapURL.absoluteString
                == "https://www.openstreetmap.org/copyright"
        )
        #expect(ExternalServiceAttribution.openStreetMapLabel == "© OpenStreetMap contributors")
    }

    @Test("iNaturalist media keeps only permissive licenses and complete attribution")
    func iNaturalistMediaLicensing() throws {
        let data = Data(
            """
            {
              "results": [
                {
                  "id": 101,
                  "observed_on": "2026-07-10",
                  "location": "30.3,-86.0",
                  "place_guess": "Inlet Beach",
                  "user": { "login": "angler_one", "name": "Angler One" },
                  "photos": [{
                    "url": "https://static.inaturalist.org/photos/101/square.jpg",
                    "license_code": "cc-by",
                    "attribution": "(c) Angler One, some rights reserved (CC BY)"
                  }]
                },
                {
                  "id": 102,
                  "observed_on": "2026-07-09",
                  "location": "30.4,-86.1",
                  "user": { "login": "private_user" },
                  "photos": [{
                    "url": "https://static.inaturalist.org/photos/102/square.jpg",
                    "license_code": "cc-by-nc",
                    "attribution": "(c) private_user, some rights reserved (CC BY-NC)"
                  }]
                },
                {
                  "id": 103,
                  "observed_on": "2026-07-08",
                  "location": "30.5,-86.2",
                  "user": { "login": "missing_credit" },
                  "photos": [{
                    "url": "https://static.inaturalist.org/photos/103/square.jpg",
                    "license_code": "cc0"
                  }]
                },
                {
                  "id": 104,
                  "observed_on": "2026-07-07",
                  "location": "30.6,-86.3",
                  "user": { "login": "public_domain" },
                  "photos": [{
                    "url": "https://static.inaturalist.org/photos/104/square.jpg",
                    "license_code": "pd",
                    "attribution": "Public domain · public_domain"
                  }]
                }
              ]
            }
            """.utf8
        )

        let sightings = try INaturalistClient.sightings(from: data)
        #expect(sightings.count == 4)

        let licensed = try #require(sightings.first(where: { $0.id == 101 }))
        #expect(licensed.creator == "Angler One")
        #expect(licensed.observationURL.absoluteString == "https://www.inaturalist.org/observations/101")
        #expect(licensed.photo?.thumbnailURL.absoluteString == "https://static.inaturalist.org/photos/101/square.jpg")
        #expect(licensed.photo?.licenseCode == "CC BY")
        #expect(licensed.photo?.licenseURL.absoluteString == "https://creativecommons.org/licenses/by/4.0/")
        #expect(licensed.photo?.attribution == "(c) Angler One, some rights reserved (CC BY)")

        #expect(sightings.first(where: { $0.id == 102 })?.photo == nil)
        #expect(sightings.first(where: { $0.id == 103 })?.photo == nil)

        let publicDomain = try #require(sightings.first(where: { $0.id == 104 }))
        #expect(publicDomain.photo?.licenseCode == "Public Domain")
        #expect(
            publicDomain.photo?.licenseURL.absoluteString
                == "https://creativecommons.org/publicdomain/mark/1.0/"
        )
    }
}
