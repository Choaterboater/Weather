import Foundation
import SwiftUI

enum ForecastFactorGroup: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fishing
    case weather
    case wind
    case waterAndSky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fishing: "Fishing"
        case .weather: "Weather"
        case .wind: "Wind"
        case .waterAndSky: "Water & Sky"
        }
    }

    var symbolName: String {
        switch self {
        case .fishing: "fish.fill"
        case .weather: "cloud.sun.fill"
        case .wind: "wind"
        case .waterAndSky: "water.waves"
        }
    }
}

/// One provider-backed matrix row. The catalog has no closures so row identity,
/// ordering, and availability remain deterministic and easy to test.
struct ForecastFactorRow: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Hashable, Identifiable, Sendable {
        case biteScore
        case solunarWindow
        case condition
        case precipitationChance
        case precipitationAmount
        case temperature
        case feelsLike
        case dewPoint
        case humidity
        case visibility
        case cloudCover
        case uvIndex
        case pressure
        case pressureTrend
        case windDirection
        case windSpeed
        case windGust
        case tideHeight
        case tideMovement
        case nextTideTurn
        case moonPhase
        case sunrise
        case sunset

        var id: String { rawValue }
    }

    let id: ID
    let group: ForecastFactorGroup
    let title: String
    let symbolName: String

    static func rows(for points: [ForecastPoint]) -> [ForecastFactorRow] {
        catalog.filter { row in points.contains(where: row.hasValue) }
    }

    func formattedValue(
        for point: ForecastPoint,
        locale: Locale,
        timeZone: TimeZone
    ) -> String? {
        switch id {
        case .biteScore:
            guard let score = point.biteScore,
                  let band = BiteScoreBand.band(for: score) else {
                return nil
            }
            return "\(score) · \(band.title)"
        case .solunarWindow:
            guard let window = point.solunarWindow else { return nil }
            return "\(window.period.rawValue) · \(window.cause)"
        case .condition:
            let value = point.weather.conditionText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return value.isEmpty ? nil : value
        case .precipitationChance:
            return Self.percent(
                Self.fraction(point.weather.precipitationChance),
                locale: locale
            )
        case .precipitationAmount:
            guard let millimeters = Self.nonnegative(
                point.weather.precipitationMM
            ) else {
                return nil
            }
            return Self.precipitation(millimeters: millimeters, locale: locale)
        case .temperature:
            guard point.weather.temperatureCelsius.isFinite else { return nil }
            return WeatherUnits.wholeTemperature(
                celsius: point.weather.temperatureCelsius,
                locale: locale
            )
        case .feelsLike:
            guard let value = Self.finite(point.weather.apparentTemperatureCelsius) else {
                return nil
            }
            return WeatherUnits.wholeTemperature(celsius: value, locale: locale)
        case .dewPoint:
            guard let value = Self.finite(point.weather.dewPointCelsius) else {
                return nil
            }
            return WeatherUnits.wholeTemperature(celsius: value, locale: locale)
        case .humidity:
            return Self.percent(
                Self.fraction(point.weather.humidityFraction),
                locale: locale
            )
        case .visibility:
            guard let meters = Self.nonnegative(point.weather.visibilityMeters) else {
                return nil
            }
            return Self.distance(meters: meters, locale: locale)
        case .cloudCover:
            return Self.percent(
                Self.fraction(point.weather.cloudCoverFraction),
                locale: locale
            )
        case .uvIndex:
            guard let value = point.weather.uvIndex, value >= 0 else { return nil }
            return value.formatted(.number.locale(locale))
        case .pressure:
            guard let value = Self.positive(point.weather.pressureHPa) else {
                return nil
            }
            return "\(Self.number(value, maximumFractionDigits: 0, locale: locale)) hPa"
        case .pressureTrend:
            return point.pressureTendency?.label
        case .windDirection:
            let degrees = point.weather.wind.directionDegrees
            guard degrees.isFinite, (0...360).contains(degrees) else { return nil }
            return "\(WeatherUnits.compassAbbreviation(degrees: degrees)) \(Int(degrees.rounded()))°"
        case .windSpeed:
            let value = point.weather.wind.speedMetersPerSecond
            guard value.isFinite, value >= 0 else { return nil }
            return Self.speed(metersPerSecond: value, locale: locale)
        case .windGust:
            guard let value = Self.nonnegative(
                point.weather.wind.gustMetersPerSecond
            ) else {
                return nil
            }
            return Self.speed(metersPerSecond: value, locale: locale)
        case .tideHeight:
            guard let value = Self.finite(point.tideHeightFeet) else { return nil }
            return Self.tideHeight(feet: value, locale: locale)
        case .tideMovement:
            let phase = point.tidePhase?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rate = Self.finite(point.tideRateFeetPerHour)
            guard phase?.isEmpty == false || rate != nil else { return nil }
            let rateText = rate.map { Self.tideRate(feetPerHour: $0, locale: locale) }
            return [phase, rateText].compactMap { $0 }.joined(separator: " · ")
        case .nextTideTurn:
            guard let event = point.nextTideTurn,
                  Self.finite(event.time) else { return nil }
            let time = ForecastDateFormatting.string(
                from: event.time,
                presentation: .time,
                timeZone: timeZone,
                locale: locale
            )
            return "\(event.kind.label) \(time)"
        case .moonPhase:
            guard let phase = point.moonPhase, phase != .unknown else { return nil }
            return phase.displayName
        case .sunrise:
            return Self.time(point.sunrise, locale: locale, timeZone: timeZone)
        case .sunset:
            return Self.time(point.sunset, locale: locale, timeZone: timeZone)
        }
    }

    private func hasValue(_ point: ForecastPoint) -> Bool {
        switch id {
        case .biteScore:
            point.biteScore.flatMap(BiteScoreBand.band(for:)) != nil
        case .solunarWindow:
            point.solunarWindow != nil
        case .condition:
            !point.weather.conditionText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .precipitationChance:
            Self.fraction(point.weather.precipitationChance) != nil
        case .precipitationAmount:
            Self.nonnegative(point.weather.precipitationMM) != nil
        case .temperature:
            point.weather.temperatureCelsius.isFinite
        case .feelsLike:
            Self.finite(point.weather.apparentTemperatureCelsius) != nil
        case .dewPoint:
            Self.finite(point.weather.dewPointCelsius) != nil
        case .humidity:
            Self.fraction(point.weather.humidityFraction) != nil
        case .visibility:
            Self.nonnegative(point.weather.visibilityMeters) != nil
        case .cloudCover:
            Self.fraction(point.weather.cloudCoverFraction) != nil
        case .uvIndex:
            point.weather.uvIndex.map { $0 >= 0 } ?? false
        case .pressure:
            Self.positive(point.weather.pressureHPa) != nil
        case .pressureTrend:
            point.pressureTendency != nil
        case .windDirection:
            point.weather.wind.directionDegrees.isFinite
                && (0...360).contains(point.weather.wind.directionDegrees)
        case .windSpeed:
            point.weather.wind.speedMetersPerSecond.isFinite
                && point.weather.wind.speedMetersPerSecond >= 0
        case .windGust:
            Self.nonnegative(point.weather.wind.gustMetersPerSecond) != nil
        case .tideHeight:
            Self.finite(point.tideHeightFeet) != nil
        case .tideMovement:
            point.tidePhase?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || Self.finite(point.tideRateFeetPerHour) != nil
        case .nextTideTurn:
            point.nextTideTurn.map { Self.finite($0.time) } ?? false
        case .moonPhase:
            point.moonPhase.map { $0 != .unknown } ?? false
        case .sunrise:
            point.sunrise.map(Self.finite) ?? false
        case .sunset:
            point.sunset.map(Self.finite) ?? false
        }
    }

    private static let catalog: [ForecastFactorRow] = [
        .init(id: .biteScore, group: .fishing, title: "Bite score", symbolName: "gauge.with.dots.needle.50percent"),
        .init(id: .solunarWindow, group: .fishing, title: "Solunar", symbolName: "moon.stars.fill"),
        .init(id: .condition, group: .weather, title: "Condition", symbolName: "cloud.sun.fill"),
        .init(id: .precipitationChance, group: .weather, title: "Precip chance", symbolName: "drop.fill"),
        .init(id: .precipitationAmount, group: .weather, title: "Precip amount", symbolName: "drop.triangle.fill"),
        .init(id: .temperature, group: .weather, title: "Temperature", symbolName: "thermometer.medium"),
        .init(id: .feelsLike, group: .weather, title: "Feels like", symbolName: "thermometer.sun.fill"),
        .init(id: .dewPoint, group: .weather, title: "Dew point", symbolName: "humidity.fill"),
        .init(id: .humidity, group: .weather, title: "Humidity", symbolName: "humidity"),
        .init(id: .visibility, group: .weather, title: "Visibility", symbolName: "eye.fill"),
        .init(id: .cloudCover, group: .weather, title: "Cloud cover", symbolName: "cloud.fill"),
        .init(id: .uvIndex, group: .weather, title: "UV index", symbolName: "sun.max.fill"),
        .init(id: .pressure, group: .weather, title: "Pressure", symbolName: "barometer"),
        .init(id: .pressureTrend, group: .weather, title: "Pressure trend", symbolName: "chart.line.uptrend.xyaxis"),
        .init(id: .windDirection, group: .wind, title: "Direction", symbolName: "location.north.fill"),
        .init(id: .windSpeed, group: .wind, title: "Sustained", symbolName: "wind"),
        .init(id: .windGust, group: .wind, title: "Gusts", symbolName: "wind.snow"),
        .init(id: .tideHeight, group: .waterAndSky, title: "Tide height", symbolName: "water.waves"),
        .init(id: .tideMovement, group: .waterAndSky, title: "Tide movement", symbolName: "arrow.up.and.down"),
        .init(id: .nextTideTurn, group: .waterAndSky, title: "Next turn", symbolName: "clock.arrow.2.circlepath"),
        .init(id: .moonPhase, group: .waterAndSky, title: "Moon phase", symbolName: "moonphase.full.moon"),
        .init(id: .sunrise, group: .waterAndSky, title: "Sunrise", symbolName: "sunrise.fill"),
        .init(id: .sunset, group: .waterAndSky, title: "Sunset", symbolName: "sunset.fill"),
    ]

    private static func finite(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func fraction(_ value: Double?) -> Double? {
        finite(value).flatMap { (0...1).contains($0) ? $0 : nil }
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        finite(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func positive(_ value: Double?) -> Double? {
        finite(value).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func finite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func percent(_ value: Double?, locale: Locale) -> String? {
        guard let value else { return nil }
        return value.formatted(
            .percent.precision(.fractionLength(0)).locale(locale)
        )
    }

    private static func number(
        _ value: Double,
        maximumFractionDigits: Int,
        locale: Locale
    ) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...maximumFractionDigits))
                .locale(locale)
        )
    }

    private static func precipitation(
        millimeters: Double,
        locale: Locale
    ) -> String {
        if locale.measurementSystem == .us {
            let inches = Measurement(
                value: millimeters,
                unit: UnitLength.millimeters
            ).converted(to: .inches).value
            return "\(number(inches, maximumFractionDigits: 2, locale: locale)) in"
        }
        return "\(number(millimeters, maximumFractionDigits: 1, locale: locale)) mm"
    }

    private static func distance(meters: Double, locale: Locale) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        if locale.measurementSystem == .us {
            let miles = measurement.converted(to: .miles).value
            return "\(number(miles, maximumFractionDigits: 1, locale: locale)) mi"
        }
        let kilometers = measurement.converted(to: .kilometers).value
        return "\(number(kilometers, maximumFractionDigits: 1, locale: locale)) km"
    }

    private static func speed(
        metersPerSecond: Double,
        locale: Locale
    ) -> String {
        let measurement = Measurement(
            value: metersPerSecond,
            unit: UnitSpeed.metersPerSecond
        )
        if locale.measurementSystem == .us {
            let mph = measurement.converted(to: .milesPerHour).value
            return "\(number(mph, maximumFractionDigits: 0, locale: locale)) mph"
        }
        let kilometersPerHour = measurement.converted(
            to: .kilometersPerHour
        ).value
        return "\(number(kilometersPerHour, maximumFractionDigits: 0, locale: locale)) km/h"
    }

    private static func tideHeight(feet: Double, locale: Locale) -> String {
        if locale.measurementSystem == .us {
            return "\(number(feet, maximumFractionDigits: 1, locale: locale)) ft"
        }
        let meters = Measurement(value: feet, unit: UnitLength.feet)
            .converted(to: .meters).value
        return "\(number(meters, maximumFractionDigits: 1, locale: locale)) m"
    }

    private static func tideRate(
        feetPerHour: Double,
        locale: Locale
    ) -> String {
        if locale.measurementSystem == .us {
            return "\(number(feetPerHour, maximumFractionDigits: 1, locale: locale)) ft/h"
        }
        let metersPerHour = Measurement(
            value: feetPerHour,
            unit: UnitLength.feet
        ).converted(to: .meters).value
        return "\(number(metersPerHour, maximumFractionDigits: 1, locale: locale)) m/h"
    }

    private static func time(
        _ date: Date?,
        locale: Locale,
        timeZone: TimeZone
    ) -> String? {
        guard let date, finite(date) else { return nil }
        return ForecastDateFormatting.string(
            from: date,
            presentation: .time,
            timeZone: timeZone,
            locale: locale
        )
    }
}

struct ForecastFactorPreferences: Equatable, Sendable {
    enum MoveDirection: Sendable {
        case earlier
        case later
    }

    private(set) var orderedGroups: [ForecastFactorGroup]
    private(set) var collapsedGroups: Set<ForecastFactorGroup>

    init(
        storedOrder: String = "",
        storedCollapsed: String = ""
    ) {
        var seen = Set<ForecastFactorGroup>()
        let decodedOrder = storedOrder
            .split(separator: ",")
            .compactMap { ForecastFactorGroup(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        orderedGroups = decodedOrder + ForecastFactorGroup.allCases.filter {
            !seen.contains($0)
        }
        collapsedGroups = Set(
            storedCollapsed
                .split(separator: ",")
                .compactMap { ForecastFactorGroup(rawValue: String($0)) }
        )
    }

    var storedOrder: String {
        orderedGroups.map(\.rawValue).joined(separator: ",")
    }

    var storedCollapsed: String {
        ForecastFactorGroup.allCases
            .filter(collapsedGroups.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    mutating func toggleCollapsed(_ group: ForecastFactorGroup) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    func canMove(
        _ group: ForecastFactorGroup,
        direction: MoveDirection
    ) -> Bool {
        canMove(group, direction: direction, among: Set(orderedGroups))
    }

    func canMove(
        _ group: ForecastFactorGroup,
        direction: MoveDirection,
        among availableGroups: Set<ForecastFactorGroup>
    ) -> Bool {
        let visible = orderedGroups.filter(availableGroups.contains)
        guard let index = visible.firstIndex(of: group) else { return false }
        return switch direction {
        case .earlier: index > visible.startIndex
        case .later: index < visible.index(before: visible.endIndex)
        }
    }

    mutating func move(
        _ group: ForecastFactorGroup,
        direction: MoveDirection
    ) {
        move(group, direction: direction, among: Set(orderedGroups))
    }

    mutating func move(
        _ group: ForecastFactorGroup,
        direction: MoveDirection,
        among availableGroups: Set<ForecastFactorGroup>
    ) {
        let visible = orderedGroups.filter(availableGroups.contains)
        guard let visibleIndex = visible.firstIndex(of: group),
              canMove(group, direction: direction, among: availableGroups) else {
            return
        }
        let targetVisibleIndex = switch direction {
        case .earlier: visible.index(before: visibleIndex)
        case .later: visible.index(after: visibleIndex)
        }
        guard let index = orderedGroups.firstIndex(of: group),
              let target = orderedGroups.firstIndex(of: visible[targetVisibleIndex]) else {
            return
        }
        orderedGroups.swapAt(index, target)
    }
}

/// A validated presentation model shared by the selected-hour detail and the
/// matrix row formatters. Invalid provider values stay unavailable everywhere.
struct ForecastSelectedDetailContent: Equatable, Sendable {
    let condition: String?
    let temperature: String?
    let biteScore: Int?
    let biteBand: BiteScoreBand?

    init(point: ForecastPoint, locale: Locale, timeZone: TimeZone) {
        let rows = ForecastFactorRow.rows(for: [point])
        func formatted(_ id: ForecastFactorRow.ID) -> String? {
            rows.first { $0.id == id }?.formattedValue(
                for: point,
                locale: locale,
                timeZone: timeZone
            )
        }

        condition = formatted(.condition)
        temperature = formatted(.temperature)
        if let score = point.biteScore,
           formatted(.biteScore) != nil,
           let band = BiteScoreBand.band(for: score) {
            biteScore = score
            biteBand = band
        } else {
            biteScore = nil
            biteBand = nil
        }
    }
}

enum ProForecastHorizon: String, CaseIterable, Identifiable, Sendable {
    case day
    case week

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    static func available(for points: [ForecastPoint]) -> [ProForecastHorizon] {
        let dates = Array(Set(points.map(\.date)))
            .filter { $0.timeIntervalSinceReferenceDate.isFinite }
            .sorted()
        guard !dates.isEmpty else { return [] }

        var contiguousHours = 1
        var hasWeek = false
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            contiguousHours = abs(gap - 3_600) <= 90
                ? contiguousHours + 1
                : 1
            if contiguousHours >= 7 * 24 {
                hasWeek = true
                break
            }
        }
        return hasWeek ? [.day, .week] : [.day]
    }
}

/// Dense provider-neutral hourly detail without a second forecast pipeline.
/// The fixed factor rail sits beside one horizontal `LazyHGrid`, so every hour
/// column stays vertically aligned while the parent BiteTime screen owns the
/// vertical scrolling behavior.
struct ProForecastMatrix: View {
    let points: [ForecastPoint]
    let timeZone: TimeZone
    let now: Date
    @Binding var selectedDate: Date?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage private var storedGroupOrder: String
    @AppStorage private var storedCollapsedGroups: String
    @State private var horizon: ProForecastHorizon = .day
    @State private var horizontalAnchor: Date?

    @ScaledMetric(relativeTo: .body) private var factorWidth: CGFloat = 154
    @ScaledMetric(relativeTo: .body) private var hourWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 76
    @ScaledMetric(relativeTo: .body) private var groupHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var factorHeight: CGFloat = 58

    init(
        points: [ForecastPoint],
        selectedDate: Binding<Date?>,
        timeZone: TimeZone = .current,
        now: Date = .now,
        preferencesStore: UserDefaults? = nil
    ) {
        self.points = points
        _selectedDate = selectedDate
        self.timeZone = timeZone
        self.now = now
        _storedGroupOrder = AppStorage(
            wrappedValue: "",
            "proForecast.groupOrder",
            store: preferencesStore
        )
        _storedCollapsedGroups = AppStorage(
            wrappedValue: "",
            "proForecast.collapsedGroups",
            store: preferencesStore
        )
        _horizontalAnchor = State(
            initialValue: selectedDate.wrappedValue ?? points.first?.date
        )
    }

    private var preferences: ForecastFactorPreferences {
        ForecastFactorPreferences(
            storedOrder: storedGroupOrder,
            storedCollapsed: storedCollapsedGroups
        )
    }

    private var resolvedFactorWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? min(factorWidth, 200) : factorWidth
    }

    private var resolvedHourWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? min(hourWidth, 160) : hourWidth
    }

    private var availableHorizons: [ProForecastHorizon] {
        ProForecastHorizon.available(for: points)
    }

    private var selectedPoint: ForecastPoint? {
        selectedDate.flatMap { ForecastSelection.nearest(to: $0, in: points) }
            ?? points.first
    }

    private var visiblePoints: [ForecastPoint] {
        guard horizon == .day else { return points }
        guard let activeDate = selectedPoint?.date else { return points }
        let calendar = forecastCalendar
        return points.filter {
            calendar.isDate($0.date, inSameDayAs: activeDate)
        }
    }

    private var forecastCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    private var availableDays: [Date] {
        var seen = Set<Date>()
        return points
            .map { forecastCalendar.startOfDay(for: $0.date) }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private var layoutRows: [ProForecastLayoutRow] {
        let availableRows = ForecastFactorRow.rows(for: points)
        return preferences.orderedGroups.flatMap { group -> [ProForecastLayoutRow] in
            let rows = availableRows.filter { $0.group == group }
            guard !rows.isEmpty else { return [] }
            var result = [ProForecastLayoutRow(content: .group(group))]
            if !preferences.collapsedGroups.contains(group) {
                result.append(contentsOf: rows.map {
                    ProForecastLayoutRow(content: .factor($0))
                })
            }
            return result
        }
    }

    private var availableGroups: Set<ForecastFactorGroup> {
        Set(ForecastFactorRow.rows(for: points).map(\.group))
    }

    private var lazyGridRows: [GridItem] {
        [GridItem(.fixed(headerHeight), spacing: 0)]
            + layoutRows.map {
                GridItem(.fixed(height(for: $0)), spacing: 0)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let selectedPoint {
                ProForecastSelectedDetail(
                    point: selectedPoint,
                    timeZone: timeZone
                )
            }

            if points.isEmpty {
                ContentUnavailableView(
                    "Hourly factors unavailable",
                    systemImage: "tablecells",
                    description: Text(
                        "This weather source did not return an hourly forecast."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                matrix
                biteLegend
            }
        }
        .onAppear(perform: normalizeStoredPreferences)
        .onChange(of: selectedDate) { _, newValue in
            horizontalAnchor = newValue
        }
        .onChange(of: points.map(\.date)) {
            if !availableHorizons.contains(horizon) {
                horizon = .day
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    forecastTitle
                    Spacer()
                    forecastSourceLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    forecastTitle
                    forecastSourceLabel
                }
            }

            HStack(spacing: 8) {
                ForEach(availableHorizons) { option in
                    Button {
                        horizon = option
                    } label: {
                        Text(option.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(horizon == option ? Ink.abyss : Ink.chartDim)
                    .background(
                        horizon == option ? Ink.brass : Ink.hull,
                        in: .capsule
                    )
                    .overlay(
                        Capsule().stroke(
                            horizon == option ? Ink.brass : Ink.hullLine,
                            lineWidth: 1
                        )
                    )
                    .accessibilityIdentifier("proForecast.horizon.\(option.rawValue)")
                    .accessibilityAddTraits(horizon == option ? .isSelected : [])
                }

                Spacer(minLength: 4)

                if horizon == .day, availableDays.count > 1 {
                    dayNavigation
                }
            }
        }
    }

    private var forecastTitle: some View {
        Label("Pro Forecast", systemImage: "tablecells")
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Ink.chart)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var forecastSourceLabel: some View {
        Text("Hourly source data")
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(Ink.chartDim)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dayNavigation: some View {
        HStack(spacing: 4) {
            Button {
                moveDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDay(by: -1))
            .accessibilityLabel("Previous forecast day")

            Text(activeDayLabel)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.chart)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Forecast day \(activeDayLabel)")

            Button {
                moveDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDay(by: 1))
            .accessibilityLabel("Next forecast day")
        }
        .background(Ink.hull.opacity(0.8), in: .capsule)
    }

    private var matrix: some View {
        HStack(alignment: .top, spacing: 0) {
            factorRail

            Rectangle()
                .fill(Ink.hullLine)
                .frame(width: 1)

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHGrid(rows: lazyGridRows, alignment: .top, spacing: 0) {
                    ForEach(visiblePoints) { point in
                        ProForecastHourHeader(
                            point: point,
                            width: resolvedHourWidth,
                            height: headerHeight,
                            timeZone: timeZone,
                            isCurrent: isCurrent(point),
                            isSelected: isSelected(point),
                            select: { select(point) }
                        )

                        ForEach(layoutRows) { layoutRow in
                            switch layoutRow.content {
                            case .group:
                                ProForecastGroupBand(
                                    width: resolvedHourWidth,
                                    height: height(for: layoutRow),
                                    isCurrent: isCurrent(point),
                                    isSelected: isSelected(point)
                                )
                            case .factor(let row):
                                ProForecastValueCell(
                                    row: row,
                                    point: point,
                                    width: resolvedHourWidth,
                                    height: height(for: layoutRow),
                                    timeZone: timeZone,
                                    isCurrent: isCurrent(point),
                                    isSelected: isSelected(point),
                                    select: { select(point) }
                                )
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $horizontalAnchor, anchor: .center)
            .accessibilityLabel("Hourly Pro Forecast columns")
            .accessibilityIdentifier("proForecast.columns")
        }
        .background(Ink.card.opacity(0.98), in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Ink.hullLine, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proForecast.matrix")
    }

    private var factorRail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Factor")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Text("Tap an hour")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }
            .padding(.horizontal, 12)
            .frame(width: resolvedFactorWidth, height: headerHeight, alignment: .leading)
            .background(Ink.hull)

            ForEach(layoutRows) { layoutRow in
                switch layoutRow.content {
                case .group(let group):
                    groupRailRow(group, layoutRow: layoutRow)
                case .factor(let row):
                    Label(row.title, systemImage: row.symbolName)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Ink.chart)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .frame(
                            width: resolvedFactorWidth,
                            height: height(for: layoutRow),
                            alignment: .leading
                        )
                        .background(Ink.card)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Ink.hullLine.opacity(0.6))
                                .frame(height: 1)
                        }
                        .accessibilityIdentifier("proForecast.row.\(row.id.rawValue)")
                }
            }
        }
    }

    private func groupRailRow(
        _ group: ForecastFactorGroup,
        layoutRow: ProForecastLayoutRow
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                updatePreferences { $0.toggleCollapsed(group) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: preferences.collapsedGroups.contains(group)
                          ? "chevron.right"
                          : "chevron.down")
                    Text(group.title)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(preferences.collapsedGroups.contains(group) ? "Expand" : "Collapse") \(group.title) group"
            )
            .accessibilityIdentifier("proForecast.group.\(group.rawValue).toggle")

            Menu {
                Button("Move \(group.title) earlier", systemImage: "arrow.up") {
                    updatePreferences {
                        $0.move(group, direction: .earlier, among: availableGroups)
                    }
                }
                .disabled(!preferences.canMove(
                    group,
                    direction: .earlier,
                    among: availableGroups
                ))

                Button("Move \(group.title) later", systemImage: "arrow.down") {
                    updatePreferences {
                        $0.move(group, direction: .later, among: availableGroups)
                    }
                }
                .disabled(!preferences.canMove(
                    group,
                    direction: .later,
                    among: availableGroups
                ))
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Reorder \(group.title) group")
            .accessibilityIdentifier("proForecast.group.\(group.rawValue).menu")
        }
        .foregroundStyle(Ink.chart)
        .padding(.leading, 12)
        .frame(
            width: resolvedFactorWidth,
            height: height(for: layoutRow),
            alignment: .leading
        )
        .background(Ink.hull)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Ink.hullLine)
                .frame(height: 1)
        }
    }

    private var biteLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Bite score legend")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.chartDim)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { biteLegendItems }
                VStack(alignment: .leading, spacing: 7) { biteLegendItems }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var biteLegendItems: some View {
        ForEach(BiteScoreBand.allCases) { band in
            ProForecastLegendItem(
                color: band.color,
                text: "\(band.title) \(band.rangeLabel)"
            )
        }
    }

    private var activeDayIndex: Int? {
        guard let selectedPoint else { return nil }
        let day = forecastCalendar.startOfDay(for: selectedPoint.date)
        return availableDays.firstIndex(of: day)
    }

    private var activeDayLabel: String {
        guard let index = activeDayIndex else { return "Day" }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = timeZone
        style.locale = locale
        return availableDays[index].formatted(style)
    }

    private func canMoveDay(by offset: Int) -> Bool {
        guard let index = activeDayIndex else { return false }
        return availableDays.indices.contains(index + offset)
    }

    private func moveDay(by offset: Int) {
        guard let index = activeDayIndex,
              availableDays.indices.contains(index + offset) else { return }
        let targetDay = availableDays[index + offset]
        guard let point = points.first(where: {
            forecastCalendar.isDate($0.date, inSameDayAs: targetDay)
        }) else { return }
        select(point)
    }

    private func select(_ point: ForecastPoint) {
        guard selectedDate != point.date else { return }
        selectedDate = point.date
        horizontalAnchor = point.date
    }

    private func isSelected(_ point: ForecastPoint) -> Bool {
        selectedDate == point.date
    }

    private func isCurrent(_ point: ForecastPoint) -> Bool {
        forecastCalendar.isDate(point.date, equalTo: now, toGranularity: .hour)
    }

    private func height(for row: ProForecastLayoutRow) -> CGFloat {
        switch row.content {
        case .group: groupHeight
        case .factor: factorHeight
        }
    }

    private func updatePreferences(
        _ update: (inout ForecastFactorPreferences) -> Void
    ) {
        var value = preferences
        update(&value)
        storedGroupOrder = value.storedOrder
        storedCollapsedGroups = value.storedCollapsed
    }

    private func normalizeStoredPreferences() {
        let value = preferences
        if storedGroupOrder != value.storedOrder {
            storedGroupOrder = value.storedOrder
        }
        if storedCollapsedGroups != value.storedCollapsed {
            storedCollapsedGroups = value.storedCollapsed
        }
    }
}

private struct ProForecastLayoutRow: Identifiable {
    enum Content {
        case group(ForecastFactorGroup)
        case factor(ForecastFactorRow)
    }

    let content: Content

    var id: String {
        switch content {
        case .group(let group): "group.\(group.rawValue)"
        case .factor(let row): "factor.\(row.id.rawValue)"
        }
    }

}

private struct ProForecastHourHeader: View {
    let point: ForecastPoint
    let width: CGFloat
    let height: CGFloat
    let timeZone: TimeZone
    let isCurrent: Bool
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                Text(ForecastDateFormatting.string(
                    from: point.date,
                    presentation: .hour,
                    timeZone: timeZone,
                    locale: locale
                ))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(isSelected ? Ink.abyss : Ink.chart)
                statusView
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? Ink.abyss : Ink.chartDim)
                    .frame(maxWidth: max(width - 12, 44))
            }
            .frame(width: width, height: height)
            .background(background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Ink.hullLine)
                    .frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ForecastDateFormatting.string(
                from: point.date,
                presentation: .dateTime,
                timeZone: timeZone,
                locale: locale
            )
        )
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint("Select this hour across BiteTime")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "proForecast.hour.\(Int(point.date.timeIntervalSince1970))"
        )
        .id(point.date)
    }

    @ViewBuilder
    private var statusView: some View {
        if isCurrent && isSelected {
            if dynamicTypeSize.isAccessibilitySize {
                stackedStatus
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        statusLabel("Now", kind: "now")
                        Text("·")
                            .accessibilityHidden(true)
                        statusLabel("Selected", kind: "selected")
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    stackedStatus
                }
            }
        } else if isSelected {
            statusLabel("Selected", kind: "selected")
        } else if isCurrent {
            statusLabel("Now", kind: "now")
        } else {
            Text("Forecast")
        }
    }

    private func statusLabel(_ title: String, kind: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .accessibilityIdentifier(
                "proForecast.hour.\(Int(point.date.timeIntervalSince1970)).status.\(kind)"
            )
    }

    private var stackedStatus: some View {
        VStack(spacing: 0) {
            statusLabel("Now", kind: "now")
            statusLabel("Selected", kind: "selected")
        }
    }

    private var accessibilityStatus: String {
        if isCurrent && isSelected { return "Now, selected" }
        if isSelected { return "Selected" }
        if isCurrent { return "Now" }
        return "Forecast"
    }

    private var background: Color {
        if isSelected { return Ink.brass }
        if isCurrent { return Ink.tide.opacity(0.24) }
        return Ink.hull
    }
}

private struct ProForecastGroupBand: View {
    let width: CGFloat
    let height: CGFloat
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(isSelected ? Ink.brass.opacity(0.16) : Ink.hull.opacity(0.82))
            .frame(width: width, height: height)
            .overlay {
                if isCurrent && !isSelected {
                    Rectangle().stroke(
                        Ink.tide,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Ink.hullLine)
                    .frame(height: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct ProForecastValueCell: View {
    let row: ForecastFactorRow
    let point: ForecastPoint
    let width: CGFloat
    let height: CGFloat
    let timeZone: TimeZone
    let isCurrent: Bool
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.locale) private var locale

    private var value: String? {
        row.formattedValue(for: point, locale: locale, timeZone: timeZone)
    }

    var body: some View {
        Button(action: select) {
            valueLabel
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(value == nil ? Ink.chartDim : Ink.chart)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 7)
                .frame(width: width, height: height)
                .background(background)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Ink.brass, lineWidth: 2)
                            .padding(2)
                    } else if isCurrent {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                Ink.tide,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                            .padding(2)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Ink.hullLine.opacity(0.6))
                        .frame(height: 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(formattedDate)")
        .accessibilityValue(value ?? "Unavailable")
        .accessibilityHint("Select this hour across BiteTime")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "proForecast.cell.\(row.id.rawValue).\(Int(point.date.timeIntervalSince1970))"
        )
    }

    @ViewBuilder
    private var valueLabel: some View {
        if row.id == .biteScore,
           let score = point.biteScore,
           let band = BiteScoreBand.band(for: score),
           let value {
            HStack(spacing: 5) {
                Circle()
                    .fill(band.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(value)
            }
        } else {
            Text(value ?? "—")
        }
    }

    private var background: Color {
        if isSelected { return Ink.brass.opacity(0.12) }
        if isCurrent { return Ink.tide.opacity(0.08) }
        return Ink.card
    }

    private var formattedDate: String {
        ForecastDateFormatting.string(
            from: point.date,
            presentation: .dateTime,
            timeZone: timeZone,
            locale: locale
        )
    }
}

private struct ProForecastSelectedDetail: View {
    let point: ForecastPoint
    let timeZone: TimeZone

    @Environment(\.locale) private var locale

    private var content: ForecastSelectedDetailContent {
        ForecastSelectedDetailContent(
            point: point,
            locale: locale,
            timeZone: timeZone
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                selectedContext
                Spacer(minLength: 8)
                selectedMetrics
            }
            VStack(alignment: .leading, spacing: 14) {
                selectedContext
                HStack(alignment: .center, spacing: 18) {
                    selectedMetrics
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(Ink.hull.opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Ink.hullLine, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proForecast.selectedDetail")
    }

    private var selectedContext: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ForecastDateFormatting.string(
                from: point.date,
                presentation: .dateTime,
                timeZone: timeZone,
                locale: locale
            ))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Ink.chart)
                .fixedSize(horizontal: false, vertical: true)
            Text(content.condition ?? "Condition unavailable")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Ink.chartDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedMetrics: some View {
        HStack(alignment: .center, spacing: 18) {
            if let temperature = content.temperature {
                Text(temperature)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Ink.chart)
            }

            if let biteScore = content.biteScore,
               let biteBand = content.biteBand {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(biteBand.color)
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text("\(biteScore)")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Ink.chart)
                    }
                    Text("Bite")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                }
            }

            if content.temperature == nil, content.biteScore == nil {
                Text("Measurements unavailable")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }
        }
    }
}

private struct ProForecastLegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.system(.caption2, design: .rounded, weight: .medium))
        } icon: {
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .foregroundStyle(Ink.chartDim)
    }
}
