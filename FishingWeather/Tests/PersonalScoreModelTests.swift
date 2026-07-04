import Foundation
import Testing
@testable import BiteCast

@Suite("PersonalScoreModel")
struct PersonalScoreModelTests {
    private func makeCatch(_ species: Species, pressure: String?,
                           moon: String? = "First Quarter", month: Int = 6,
                           wind: Double? = nil) -> CatchEntry {
        var comps = DateComponents()
        comps.year = 2025; comps.month = month; comps.day = 15
        let date = Calendar.current.date(from: comps)!
        return CatchEntry(date: date, species: species, bait: "jig",
                          pressureTendency: pressure, moonPhase: moon, windMph: wind)
    }

    private func sum(_ w: FactorWeights) -> Double {
        w.solunar + w.pressure + w.wind + w.tide + w.season
    }

    @Test("Under the catch threshold, the score stays standard")
    func coldStartReturnsStandard() {
        let catches = (0..<4).map { _ in makeCatch(.bass, pressure: "Falling") }
        #expect(PersonalScoreModel.weights(from: catches, species: .bass) == .standard)
        #expect(PersonalScoreModel.informingCatchCount(catches, species: .bass) == 0)
    }

    @Test("Consistently catching on falling pressure boosts the pressure weight")
    func fallingPressureBoostsPressureWeight() {
        let catches = (0..<15).map { _ in makeCatch(.bass, pressure: "Falling") }
        let w = PersonalScoreModel.weights(from: catches, species: .bass)
        #expect(w.pressure > FactorWeights.standard.pressure)
    }

    @Test("Personalized weights still sum to 1")
    func weightsStayNormalized() {
        let catches = (0..<20).map { i in
            makeCatch(.bass, pressure: i.isMultiple(of: 2) ? "Falling" : "Rising", month: 6)
        }
        let w = PersonalScoreModel.weights(from: catches, species: .bass)
        #expect(abs(sum(w) - 1) < 0.0001)
    }

    @Test("Unmeasured factors (wind/tide) keep their base ratio — no spurious tuning")
    func unmeasuredFactorsPreserved() {
        let catches = (0..<15).map { _ in makeCatch(.bass, pressure: "Falling") }
        let w = PersonalScoreModel.weights(from: catches, species: .bass)
        let baseRatio = FactorWeights.standard.wind / FactorWeights.standard.tide
        #expect(abs(w.wind / w.tide - baseRatio) < 0.001)
    }

    @Test("Sparse species data falls back to the full catch log")
    func perSpeciesFallbackToAll() {
        let mixed = (0..<2).map { _ in makeCatch(.bass, pressure: "Falling") }
            + (0..<15).map { _ in makeCatch(.redfish, pressure: "Falling") }
        #expect(PersonalScoreModel.informingCatchCount(mixed, species: .bass) == 17)
    }

    @Test("Wind is personalized once catches capture it")
    func windAffinityFromSnapshot() {
        // Ideal wind (8 mph → 1.0) against a weak pressure signal — wind should
        // stand out and gain weight, where without windMph it would stay put.
        let catches = (0..<15).map { _ in makeCatch(.bass, pressure: "Rising", wind: 8) }
        let w = PersonalScoreModel.weights(from: catches, species: .bass)
        #expect(w.wind > FactorWeights.standard.wind)
    }

    @Test("More catches means a stronger shift (confidence ramp)")
    func confidenceRampStrengthens() {
        func shiftMagnitude(_ n: Int) -> Double {
            let catches = (0..<n).map { _ in makeCatch(.bass, pressure: "Falling") }
            let w = PersonalScoreModel.weights(from: catches, species: .bass)
            return w.pressure - FactorWeights.standard.pressure
        }
        #expect(shiftMagnitude(15) > shiftMagnitude(7))
        #expect(shiftMagnitude(7) > 0)
    }
}
