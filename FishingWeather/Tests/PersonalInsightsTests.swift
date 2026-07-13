import Foundation
import Testing
@testable import BiteCast

@Suite("PersonalInsights")
struct PersonalInsightsTests {
    private let insightNow = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeCatch(_ species: Species = .bass, bait: String = "jig",
                           pressure: String? = "Falling", moon: String? = "Full Moon",
                           hour: Int = 6, month: Int = 6,
                           wind: Double? = nil, tide: String? = nil,
                           source: CatchConditionSource? = CatchConditionSource(
                               providerKind: .nationalWeatherService,
                               expiresAt: Date(timeIntervalSince1970: 2_000_000_900)
                           )) -> CatchEntry {
        var comps = DateComponents()
        comps.year = 2025; comps.month = month; comps.day = 15; comps.hour = hour
        let date = Calendar.current.date(from: comps)!
        return CatchEntry(date: date, species: species, bait: bait,
                          pressureTendency: pressure, moonPhase: moon,
                          windMph: wind, tidePhase: tide,
                          conditionSource: source,
                          tideSource: tide.map { _ in
                              CatchTideSource(stationID: "8720218")
                          },
                          astronomySource: source?.providerKind
                              == .nationalWeatherService
                              ? CatchAstronomySource()
                              : nil)
    }

    @Test("No insights under the catch threshold")
    func nilUnderThreshold() {
        let catches = (0..<4).map { _ in makeCatch() }
        #expect(PersonalInsightsBuilder.build(from: catches, species: .bass) == nil)
    }

    @Test("Top bait is the most frequently logged one")
    func topBaitRanked() {
        let catches = (0..<8).map { _ in makeCatch(bait: "Chatterbait") }
            + (0..<3).map { _ in makeCatch(bait: "Jig") }
        let insights = PersonalInsightsBuilder.build(from: catches, species: .bass)
        #expect(insights?.topBaits.first?.bait == "Chatterbait")
        #expect(insights?.topBaits.first?.count == 8)
    }

    @Test("Bait tally is case-insensitive")
    func baitCaseInsensitive() {
        let catches = (0..<3).map { _ in makeCatch(bait: "chatterbait") }
            + (0..<3).map { _ in makeCatch(bait: "Chatterbait") }
        let insights = PersonalInsightsBuilder.build(from: catches, species: .bass)
        #expect(insights?.topBaits.count == 1)
        #expect(insights?.topBaits.first?.count == 6)
    }

    @Test("The dominant pressure trend surfaces as a condition")
    func pressureConditionSurfaced() {
        let catches = (0..<10).map { _ in makeCatch(pressure: "Falling") }
        let insights = PersonalInsightsBuilder.build(from: catches, species: .bass)
        #expect(insights?.conditions.contains { $0.label == "Falling pressure" } == true)
    }

    @Test("Catching on falling pressure marks the pressure factor up")
    func factorChangeReflectsWeights() {
        // Quarter moons keep solunar affinity low so falling pressure stands out
        // above the reference. (A uniformly favorable pattern nets to "steady" —
        // correct behavior, but not what this test checks.)
        let catches = (0..<15).map { _ in makeCatch(pressure: "Falling", moon: "First Quarter") }
        let insights = PersonalInsightsBuilder.build(from: catches, species: .bass)
        let pressure = insights?.factorChanges.first { $0.kind == .pressure }
        #expect(pressure?.direction == .up)
    }

    @Test("Legacy and Apple conditions never influence personal learning")
    func untrustedConditionOriginsAreIgnored() {
        let legacy = (0..<6).map { _ in
            makeCatch(
                pressure: "Falling",
                moon: "Full Moon",
                wind: 8,
                tide: "Rising",
                source: nil
            )
        }
        let apple = (0..<6).map { _ in
            makeCatch(
                pressure: "Falling",
                moon: "Full Moon",
                wind: 8,
                tide: "Rising",
                source: CatchConditionSource(
                    providerKind: .appleWeather,
                    expiresAt: insightNow.addingTimeInterval(900)
                )
            )
        }
        for catches in [legacy, apple] {
            let insights = PersonalInsightsBuilder.build(
                from: catches,
                species: .bass
            )
            #expect(insights?.conditions.contains {
                $0.label.localizedCaseInsensitiveContains("pressure")
                    || $0.icon == "moon.stars"
            } == false)
            #expect(PersonalScoreModel.pressureAffinity(catches[0]) == nil)
            #expect(PersonalScoreModel.moonAffinity(catches[0]) == nil)
            #expect(PersonalScoreModel.windAffinity(catches[0]) == nil)
        }
    }

    @Test("NWS values captured while valid remain durable after provider expiry")
    func expiredNWSMetadataStillAttributesCatchHistory() {
        let expiredNWS = (0..<6).map { _ in
            makeCatch(
                pressure: "Falling",
                moon: "Full Moon",
                wind: 8,
                source: CatchConditionSource(
                    providerKind: .nationalWeatherService,
                    expiresAt: insightNow
                )
            )
        }

        let insights = PersonalInsightsBuilder.build(
            from: expiredNWS,
            species: .bass
        )
        #expect(insights?.conditions.contains {
            $0.label == "Falling pressure"
        } == true)
        #expect(PersonalScoreModel.pressureAffinity(expiredNWS[0]) == 1)
        #expect(PersonalScoreModel.moonAffinity(expiredNWS[0]) == 1)
        #expect(PersonalScoreModel.windAffinity(expiredNWS[0]) == 1)
    }
}
