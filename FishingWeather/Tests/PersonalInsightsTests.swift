import Foundation
import Testing
@testable import BiteCast

@Suite("PersonalInsights")
struct PersonalInsightsTests {
    private func makeCatch(_ species: Species = .bass, bait: String = "jig",
                           pressure: String? = "Falling", moon: String? = "Full Moon",
                           hour: Int = 6, month: Int = 6) -> CatchEntry {
        var comps = DateComponents()
        comps.year = 2025; comps.month = month; comps.day = 15; comps.hour = hour
        let date = Calendar.current.date(from: comps)!
        return CatchEntry(date: date, species: species, bait: bait,
                          pressureTendency: pressure, moonPhase: moon)
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
        let catches = (0..<15).map { _ in makeCatch(pressure: "Falling") }
        let insights = PersonalInsightsBuilder.build(from: catches, species: .bass)
        let pressure = insights?.factorChanges.first { $0.kind == .pressure }
        #expect(pressure?.direction == .up)
    }
}
