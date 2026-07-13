import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Async state identity")
struct AsyncStateIdentityTests {
    @Test("Trip requests distinguish display names at the same coordinate")
    func tripRequestsIncludeLocationName() {
        let location = CLLocation(latitude: 27.7634, longitude: -82.6403)

        let old = TripForecastLoader.requestKey(
            location: location,
            species: .bass,
            locationName: "Current spot"
        )
        let updated = TripForecastLoader.requestKey(
            location: location,
            species: .bass,
            locationName: "St. Petersburg"
        )

        #expect(old != updated)
    }

    @Test("Catch tide phase is omitted when events belong to another location")
    func tidePhaseRequiresMatchingData() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            TideEvent(time: now.addingTimeInterval(-7_200), kind: .low, heightFeet: 0.2),
            TideEvent(time: now.addingTimeInterval(7_200), kind: .high, heightFeet: 2.4),
        ]

        #expect(LogCatchView.tidePhase(events: events, hasMatchingData: false, now: now) == nil)
        #expect(LogCatchView.tidePhase(events: events, hasMatchingData: true, now: now) == "Rising")
    }

    @Test("Tide request keys distinguish rounded coordinates")
    func tideKeysIncludeLocation() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CLLocation(latitude: 27.76, longitude: -82.64)
        let b = CLLocation(latitude: 28.76, longitude: -83.64)

        #expect(TideService.dataKey(a, date: date) != TideService.dataKey(b, date: date))
    }

    @Test("An answer generation is stale after reset advances the generation")
    func staleAnswerGenerationIsRejected() {
        #expect(BaitEngine.isCurrentGeneration(3, current: 3))
        #expect(!BaitEngine.isCurrentGeneration(3, current: 4))
    }

    @MainActor
    @Test("Canceling a trip load cannot commit an outlook")
    func canceledTripLoadDoesNotCommit() async {
        let loader = TripForecastLoader(worker: { _, _, locationName in
            try? await Task.sleep(for: .seconds(10))
            return WeekOutlook(locationName: locationName, generatedAt: .now, windows: [])
        })
        let location = CLLocation(latitude: 27.76, longitude: -82.64)

        let task = Task {
            await loader.load(for: location, species: .bass, locationName: "Canceled")
        }
        await Task.yield()
        task.cancel()
        let result = await task.value

        #expect(result == nil)
        #expect(loader.outlook == nil)
        #expect(!loader.isLoading)
    }

    @MainActor
    @Test("Only one same-generation AI question runs at a time")
    func concurrentQuestionsAreRejected() async {
        let started = AsyncStartSignal()
        let engine = BaitEngine(answerWorker: { question in
            await started.markStarted()
            try await Task.sleep(for: .milliseconds(100))
            return "Answer to \(question)"
        })

        let first = Task { await engine.ask("first") }
        await started.wait()
        await engine.ask("second")
        await first.value

        #expect(engine.answers.count == 1)
        #expect(engine.answers.first?.question == "first")
        #expect(!engine.isAnswering)
    }

    @MainActor
    @Test("Reset prevents an in-flight AI answer from returning")
    func resetDropsInflightAnswer() async {
        let started = AsyncStartSignal()
        let engine = BaitEngine(answerWorker: { _ in
            await started.markStarted()
            try await Task.sleep(for: .milliseconds(100))
            return "Stale answer"
        })

        let task = Task { await engine.ask("old question") }
        await started.wait()
        engine.reset()
        await task.value

        #expect(engine.answers.isEmpty)
        #expect(!engine.isAnswering)
    }
}

private actor AsyncStartSignal {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }

    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
