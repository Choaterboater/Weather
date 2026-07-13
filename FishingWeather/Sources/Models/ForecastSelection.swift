import Foundation

/// The forecast facts an angler can inspect on the shared hourly timeline.
enum ForecastMetric: String, CaseIterable, Identifiable, Sendable {
    case temperature
    case wind
    case pressure
    case precipitation
    case biteScore

    var id: Self { self }
}

/// One provider-neutral hour shared by Timeline, hourly cells, and Pro Forecast.
struct ForecastPoint: Identifiable, Equatable, Sendable {
    var id: Date { weather.date }
    var date: Date { weather.date }

    let weather: HourlyWeatherPoint
    let biteScore: Int?
    let tideHeightFeet: Double?
    let tidePhase: String?
    let solunarWindow: BiteWindow?
    /// Exact neighboring-day window set used by the scorer. `nil` is reserved
    /// for hand-built legacy/debug points that did not capture score context;
    /// an empty array is a real forecast result with no available windows.
    let solunarWindows: [BiteWindow]?
    let pressureTendency: PressureTendency?
    let moonPhase: LunarPhase?
    let sunrise: Date?
    let sunset: Date?
    let tideRateFeetPerHour: Double?
    let nextTideTurn: TideEvent?
    /// Exact factor breakdown used to produce `biteScore`. Fishing Details
    /// consumes this value directly so it cannot drift from the hero/timeline.
    let fishingScore: FishingScore?

    init(
        weather: HourlyWeatherPoint,
        biteScore: Int?,
        tideHeightFeet: Double?,
        tidePhase: String?,
        solunarWindow: BiteWindow?,
        solunarWindows: [BiteWindow]? = nil,
        pressureTendency: PressureTendency? = nil,
        moonPhase: LunarPhase? = nil,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        tideRateFeetPerHour: Double? = nil,
        nextTideTurn: TideEvent? = nil,
        fishingScore: FishingScore? = nil
    ) {
        self.weather = weather
        self.biteScore = biteScore
        self.tideHeightFeet = tideHeightFeet
        self.tidePhase = tidePhase
        self.solunarWindow = solunarWindow
        self.solunarWindows = solunarWindows
        self.pressureTendency = pressureTendency
        self.moonPhase = moonPhase
        self.sunrise = sunrise
        self.sunset = sunset
        self.tideRateFeetPerHour = tideRateFeetPerHour
        self.nextTideTurn = nextTideTurn
        self.fishingScore = fishingScore
    }
}

enum ForecastSelection {
    static func nearest(
        to date: Date,
        in points: [ForecastPoint]
    ) -> ForecastPoint? {
        points.min { lhs, rhs in
            let lhsDistance = abs(lhs.date.timeIntervalSince(date))
            let rhsDistance = abs(rhs.date.timeIntervalSince(date))
            if lhsDistance == rhsDistance {
                return lhs.date < rhs.date
            }
            return lhsDistance < rhsDistance
        }
    }

    static func snappedDate(
        for rawDate: Date?,
        current: Date?,
        in points: [ForecastPoint]
    ) -> Date? {
        guard let rawDate,
              let snapped = nearest(to: rawDate, in: points)?.date else {
            return current
        }
        return snapped == current ? current : snapped
    }
}

/// Builds the immutable hourly series consumed by every forecast surface.
enum ForecastSeriesBuilder {
    private static let maximumHours = 48

    static func build(
        weather: WeatherSnapshot,
        tideSamples: [TideSample],
        species: Species,
        weights: FactorWeights = .standard,
        now: Date = .now
    ) -> [ForecastPoint] {
        let sortedHours = weather.hourly
            .filter { $0.date.isFinite && $0.date >= now }
            .sorted { $0.date < $1.date }
        let hours = uniqueHours(sortedHours)
            .prefix(maximumHours)
        let sortedTides = tideSamples
            .filter { $0.time.isFinite && $0.heightFeet.isFinite }
            .sorted { $0.time < $1.time }
        let tideSamples = uniqueTides(sortedTides)
        let tideEvents = extrema(in: tideSamples)
        let calendar = forecastCalendar(
            timeZoneIdentifier: weather.timeZoneIdentifier
        )
        let dayContexts = makeDayContexts(
            hours: hours,
            weather: weather,
            calendar: calendar
        )
        let pressureHistory = weather.hourly.compactMap { point in
            point.pressureHPa.map { (date: point.date, hPa: $0) }
        }

        return hours.map { hour in
            let day = calendar.startOfDay(for: hour.date)
            let context = dayContexts[day] ?? DayContext(
                moonPhase: nil,
                windows: [],
                sunrise: nil,
                sunset: nil
            )
            let windows = neighboringWindows(
                around: day,
                contexts: dayContexts,
                calendar: calendar
            )
            let activeWindow = windows.first { $0.isActive(at: hour.date) }
            let nextWindow = windows
                .filter { $0.start > hour.date }
                .min { $0.start < $1.start }
            let pressure = PressureReading.analyze(
                nowHPa: hour.pressureHPa,
                history: pressureHistory,
                now: hour.date,
                fallback: .steady
            )
            let tide = interpolatedTide(at: hour.date, samples: tideSamples)
            let pressureTendency = pressure.pressure != nil
                && pressure.changePerHour != nil
                ? pressure.tendency
                : nil
            let nextTideTurn = tide.flatMap { _ in
                tideEvents.first { $0.time > hour.date }
            }
            let score = FishingScorer.score(
                moonPhase: context.moonPhase ?? .unknown,
                activeWindow: activeWindow,
                nextWindow: nextWindow,
                pressureTendency: pressureTendency,
                pressureChangePerHour: pressure.changePerHour,
                windMph: WeatherUnits.milesPerHour(
                    metersPerSecond: hour.wind.speedMetersPerSecond
                ),
                species: species,
                tideEvents: tide == nil ? [] : tideEvents,
                weights: weights,
                now: hour.date,
                calendar: calendar
            )

            return ForecastPoint(
                weather: hour,
                biteScore: score.overall,
                tideHeightFeet: tide?.height,
                tidePhase: tide?.phase,
                solunarWindow: activeWindow,
                solunarWindows: windows,
                pressureTendency: pressureTendency,
                moonPhase: context.moonPhase,
                sunrise: context.sunrise,
                sunset: context.sunset,
                tideRateFeetPerHour: tide?.rateFeetPerHour,
                nextTideTurn: nextTideTurn,
                fishingScore: score
            )
        }
    }

    private struct DayContext {
        let moonPhase: LunarPhase?
        let windows: [BiteWindow]
        let sunrise: Date?
        let sunset: Date?
    }

    private static func makeDayContexts(
        hours: some Sequence<HourlyWeatherPoint>,
        weather: WeatherSnapshot,
        calendar: Calendar
    ) -> [Date: DayContext] {
        // Providers calculate top-level astronomy for the request fetch date.
        // Observation/current-hour timestamps and a later runtime clock can
        // straddle midnight, so neither identifies this astronomy payload.
        let astronomyDay = calendar.startOfDay(
            for: weather.provenance.fetchedAt
        )
        let dailyAstronomy: [Date: AstronomySnapshot] = weather.daily.reduce(
            into: [:]
        ) { result, day in
            guard let astronomy = day.astronomy else { return }
            let key = calendar.startOfDay(for: day.date)
            if result[key] == nil {
                result[key] = astronomy
            }
        }

        let forecastDays = Set(
            hours.map { calendar.startOfDay(for: $0.date) }
        )
        let contextDays = Set(forecastDays.flatMap { day in
            (-1...1).compactMap {
                calendar.date(byAdding: .day, value: $0, to: day)
            }
        })

        return contextDays.reduce(
            into: [:]
        ) { result, day in
            let astronomy = dailyAstronomy[day]
                ?? (day == astronomyDay ? weather.astronomy : .empty)
            let moonPhase = LunarPhase(
                cycleFraction: astronomy.moonPhaseFraction
            )
            result[day] = DayContext(
                moonPhase: moonPhase == .unknown ? nil : moonPhase,
                windows: SolunarCalculator.windows(
                    moonrise: astronomy.moonrise,
                    moonset: astronomy.moonset,
                    on: day,
                    calendar: calendar
                ),
                sunrise: astronomy.sunrise,
                sunset: astronomy.sunset
            )
        }
    }

    private static func neighboringWindows(
        around day: Date,
        contexts: [Date: DayContext],
        calendar: Calendar
    ) -> [BiteWindow] {
        (-1...1)
            .compactMap {
                calendar.date(byAdding: .day, value: $0, to: day)
            }
            .flatMap { contexts[$0]?.windows ?? [] }
            .sorted {
                if $0.start == $1.start {
                    return $0.peak < $1.peak
                }
                return $0.start < $1.start
            }
    }

    private static func forecastCalendar(
        timeZoneIdentifier: String
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    private static func uniqueHours(
        _ hours: [HourlyWeatherPoint]
    ) -> [HourlyWeatherPoint] {
        var dates = Set<Date>()
        return hours.filter { dates.insert($0.date).inserted }
    }

    private static func uniqueTides(
        _ samples: [TideSample]
    ) -> [TideSample] {
        var dates = Set<Date>()
        return samples.filter { dates.insert($0.time).inserted }
    }

    private static func interpolatedTide(
        at date: Date,
        samples: [TideSample]
    ) -> (height: Double, phase: String?, rateFeetPerHour: Double?)? {
        guard !samples.isEmpty,
              let first = samples.first,
              let last = samples.last,
              date >= first.time,
              date <= last.time else {
            return nil
        }

        if let index = samples.firstIndex(where: { $0.time == date }) {
            let rate = tideRate(at: index, samples: samples)
            return (
                samples[index].heightFeet,
                rate.map(phase(from:)),
                rate
            )
        }

        guard let upperIndex = samples.firstIndex(where: { $0.time > date }),
              upperIndex > samples.startIndex else {
            return nil
        }
        let lowerIndex = samples.index(before: upperIndex)
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let duration = upper.time.timeIntervalSince(lower.time)
        guard duration > 0 else { return nil }

        let fraction = date.timeIntervalSince(lower.time) / duration
        let height = lower.heightFeet
            + (upper.heightFeet - lower.heightFeet) * fraction
        let rate = tideRate(from: lower, to: upper)
        return (
            height,
            rate.map(phase(from:)),
            rate
        )
    }

    private static func tideRate(
        at index: Int,
        samples: [TideSample]
    ) -> Double? {
        if index + 1 < samples.count {
            return tideRate(from: samples[index], to: samples[index + 1])
        }
        if index > samples.startIndex {
            return tideRate(from: samples[index - 1], to: samples[index])
        }
        return nil
    }

    private static func tideRate(
        from lower: TideSample,
        to upper: TideSample
    ) -> Double? {
        let hours = upper.time.timeIntervalSince(lower.time) / 3_600
        guard hours > 0 else { return nil }
        return (upper.heightFeet - lower.heightFeet) / hours
    }

    private static func phase(from rateFeetPerHour: Double) -> String {
        if abs(rateFeetPerHour) < 0.01 { return "Slack" }
        return rateFeetPerHour > 0 ? "Rising" : "Falling"
    }

    /// Converts only actual curve turns into scorer events. Intermediate hourly
    /// samples remain curve data and are never mislabeled as high/low tide.
    private static func extrema(in samples: [TideSample]) -> [TideEvent] {
        guard samples.count >= 3 else { return [] }

        return samples.indices.dropFirst().dropLast().compactMap { index in
            let previous = samples[index - 1]
            let sample = samples[index]
            let next = samples[index + 1]
            let kind: TideEvent.Kind?
            if sample.heightFeet >= previous.heightFeet,
               sample.heightFeet > next.heightFeet {
                kind = .high
            } else if sample.heightFeet <= previous.heightFeet,
                      sample.heightFeet < next.heightFeet {
                kind = .low
            } else {
                kind = nil
            }

            return kind.map {
                TideEvent(
                    time: sample.time,
                    kind: $0,
                    heightFeet: sample.heightFeet
                )
            }
        }
    }
}

private extension Date {
    var isFinite: Bool { timeIntervalSinceReferenceDate.isFinite }
}
