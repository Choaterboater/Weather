import CoreLocation
import Foundation

struct LocalAstronomyProvider: Sendable {
    func snapshot(
        for location: CLLocation,
        date: Date,
        calendar: Calendar = .current
    ) -> AstronomySnapshot {
        let day = JulianDay(date)
        let coordinate = location.coordinate
        let solar = SolarEvents.calculate(
            day: day,
            coordinate: coordinate,
            calendar: calendar
        )
        let lunar = LunarEvents.calculate(
            day: day,
            coordinate: coordinate,
            calendar: calendar
        )

        return AstronomySnapshot(
            sunrise: solar.sunrise,
            sunset: solar.sunset,
            moonrise: lunar.rise,
            moonset: lunar.set,
            moonTransit: lunar.transit,
            moonPhaseFraction: lunar.phaseFraction
        )
    }
}

fileprivate struct JulianDay: Sendable {
    private static let unixEpoch = 2_440_587.5

    let value: Double
    let date: Date

    init(_ date: Date) {
        self.date = date
        value = date.timeIntervalSince1970 / 86_400 + Self.unixEpoch
    }
}

fileprivate struct SolarEvents: Sendable {
    private static let officialZenithDegrees = 90.833

    let sunrise: Date?
    let sunset: Date?

    static func calculate(
        day: JulianDay,
        coordinate: CLLocationCoordinate2D,
        calendar: Calendar
    ) -> Self {
        guard CLLocationCoordinate2DIsValid(coordinate),
              let interval = calendar.dateInterval(of: .day, for: day.date) else {
            return Self(sunrise: nil, sunset: nil)
        }

        // NOAA's conventional event is the solar center at -0.833 degrees,
        // equivalently a 90.833-degree zenith distance.
        let horizonAltitude = 90 - officialZenithDegrees
        let crossings = HorizonCrossings.find(
            in: interval,
            sampleInterval: 3_600,
            threshold: horizonAltitude
        ) { date in
            SolarPosition.altitude(
                at: JulianDay(date),
                coordinate: coordinate
            )
        }

        return Self(sunrise: crossings.rise, sunset: crossings.set)
    }
}

fileprivate struct LunarEvents: Sendable {
    private static let synodicMonthDays = 29.530588853
    // New Moon on 2000-01-06 at 18:14 UTC, expressed as a Julian day.
    private static let referenceNewMoon = 2_451_550.25972

    let rise: Date?
    let set: Date?
    let transit: Date?
    let phaseFraction: Double

    static func calculate(
        day: JulianDay,
        coordinate: CLLocationCoordinate2D,
        calendar: Calendar
    ) -> Self {
        let phaseFraction = phaseFraction(for: day)

        guard CLLocationCoordinate2DIsValid(coordinate),
              let interval = calendar.dateInterval(of: .day, for: day.date) else {
            return Self(
                rise: nil,
                set: nil,
                transit: nil,
                phaseFraction: phaseFraction
            )
        }

        // Conventional moonrise/set is apparent upper-limb contact with a
        // level horizon. Since LunarPosition returns a topocentric geometric
        // center altitude, the event function adds the dynamic semidiameter
        // and the standard 34 arcminutes of horizon refraction. This is the
        // topocentric equivalent of the average +0.125-degree geocentric
        // Moon-center threshold; applying +0.125 here would count parallax twice.
        let crossings = HorizonCrossings.find(
            in: interval,
            sampleInterval: 3_600,
            threshold: 0
        ) { date in
            LunarPosition.calculate(
                at: JulianDay(date),
                coordinate: coordinate
            ).apparentUpperLimbAltitude
        }

        let transit = AltitudeMaximum.find(
            in: interval,
            sampleInterval: 3_600
        ) { date in
            LunarPosition.calculate(
                at: JulianDay(date),
                coordinate: coordinate
            ).centerAltitude
        }

        return Self(
            rise: crossings.rise,
            set: crossings.set,
            transit: transit,
            phaseFraction: phaseFraction
        )
    }

    private static func phaseFraction(for day: JulianDay) -> Double {
        var fraction = ((day.value - referenceNewMoon) / synodicMonthDays)
            .truncatingRemainder(dividingBy: 1)
        if fraction < 0 {
            fraction += 1
        }
        return min(max(fraction, 0), 1)
    }
}

fileprivate struct HorizonCrossings: Sendable {
    let rise: Date?
    let set: Date?

    static func find(
        in interval: DateInterval,
        sampleInterval: TimeInterval,
        threshold: Double,
        altitude: (Date) -> Double
    ) -> Self {
        let coarseTimes = SamplingTimes.coarse(
            in: interval,
            sampleInterval: sampleInterval
        )
        // Hourly samples establish deterministic coarse bins. Quarter-hour
        // interior samples discover grazing arcs that can rise and set inside
        // a single bin; every discovered crossing is still bisected to a minute.
        let times = SamplingTimes.subdividing(
            coarseTimes,
            maximumInterval: 15 * 60
        )
        guard let firstTime = times.first else {
            return Self(rise: nil, set: nil)
        }

        var rise: Date?
        var set: Date?
        var previousTime = firstTime
        var previousValue = altitude(firstTime) - threshold

        for time in times.dropFirst() {
            let value = altitude(time) - threshold

            if rise == nil, previousValue <= 0, value > 0 {
                rise = refine(
                    from: previousTime,
                    to: time,
                    threshold: threshold,
                    altitude: altitude
                )
            } else if set == nil, previousValue >= 0, value < 0 {
                set = refine(
                    from: previousTime,
                    to: time,
                    threshold: threshold,
                    altitude: altitude
                )
            }

            previousTime = time
            previousValue = value
        }

        return Self(rise: rise, set: set)
    }

    private static func refine(
        from start: Date,
        to end: Date,
        threshold: Double,
        altitude: (Date) -> Double
    ) -> Date {
        var lower = start
        var upper = end
        var lowerIsAbove = altitude(lower) >= threshold

        while upper.timeIntervalSince(lower) > 60 {
            let midpoint = lower.addingTimeInterval(
                upper.timeIntervalSince(lower) / 2
            )
            let midpointIsAbove = altitude(midpoint) >= threshold

            if midpointIsAbove == lowerIsAbove {
                lower = midpoint
                lowerIsAbove = midpointIsAbove
            } else {
                upper = midpoint
            }
        }

        return lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
    }
}

fileprivate enum AltitudeMaximum {
    static func find(
        in interval: DateInterval,
        sampleInterval: TimeInterval,
        altitude: (Date) -> Double
    ) -> Date? {
        let times = SamplingTimes.coarse(
            in: interval,
            sampleInterval: sampleInterval
        )
        guard !times.isEmpty else { return nil }

        let bestIndex = times.indices.max { lhs, rhs in
            altitude(times[lhs]) < altitude(times[rhs])
        }!
        var lower = times[bestIndex > times.startIndex ? bestIndex - 1 : bestIndex]
        var upper = times[bestIndex < times.index(before: times.endIndex) ? bestIndex + 1 : bestIndex]

        // Refine the best hourly bracket to one-minute resolution. Lunar
        // declination changes during culmination, so the altitude maximum is
        // intentionally used instead of assuming a fixed meridian-crossing time.
        while upper.timeIntervalSince(lower) > 60 {
            let span = upper.timeIntervalSince(lower)
            let firstThird = lower.addingTimeInterval(span / 3)
            let secondThird = upper.addingTimeInterval(-span / 3)

            if altitude(firstThird) < altitude(secondThird) {
                lower = firstThird
            } else {
                upper = secondThird
            }
        }

        return lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
    }
}

fileprivate enum SamplingTimes {
    static func coarse(
        in interval: DateInterval,
        sampleInterval: TimeInterval
    ) -> [Date] {
        guard interval.duration > 0, sampleInterval > 0 else { return [] }

        // DateInterval is treated as half-open. The final sample is just inside
        // the next local midnight so UTC offsets and DST-length days stay exact.
        let last = interval.end.addingTimeInterval(-0.001)
        var result = [interval.start]
        var next = interval.start.addingTimeInterval(sampleInterval)

        while next < last {
            result.append(next)
            next = next.addingTimeInterval(sampleInterval)
        }
        if last > interval.start {
            result.append(last)
        }
        return result
    }

    static func subdividing(
        _ coarseTimes: [Date],
        maximumInterval: TimeInterval
    ) -> [Date] {
        guard let first = coarseTimes.first, maximumInterval > 0 else {
            return coarseTimes
        }

        var result = [first]
        for endpoint in coarseTimes.dropFirst() {
            var interior = result.last!.addingTimeInterval(maximumInterval)
            while interior < endpoint {
                result.append(interior)
                interior = interior.addingTimeInterval(maximumInterval)
            }
            result.append(endpoint)
        }
        return result
    }
}

fileprivate struct SolarPosition: Sendable {
    let rightAscension: Double
    let declination: Double

    static func altitude(
        at day: JulianDay,
        coordinate: CLLocationCoordinate2D
    ) -> Double {
        let position = calculate(at: day)
        return AstronomyMath.altitude(
            rightAscension: position.rightAscension,
            declination: position.declination,
            at: day,
            coordinate: coordinate
        )
    }

    private static func calculate(at day: JulianDay) -> Self {
        // NOAA/Meeus solar coordinates of date. Every trigonometric argument
        // is explicitly converted from the tabulated degrees to radians.
        let century = (day.value - 2_451_545) / 36_525
        let meanLongitude = AstronomyMath.normalizedDegrees(
            280.46646 + century * (36_000.76983 + century * 0.0003032)
        )
        let meanAnomaly = AstronomyMath.normalizedDegrees(
            357.52911 + century * (35_999.05029 - 0.0001537 * century)
        )
        let equationOfCenter =
            sin(AstronomyMath.radians(meanAnomaly))
                * (1.914602 - century * (0.004817 + 0.000014 * century))
            + sin(AstronomyMath.radians(2 * meanAnomaly))
                * (0.019993 - 0.000101 * century)
            + sin(AstronomyMath.radians(3 * meanAnomaly)) * 0.000289
        let trueLongitude = meanLongitude + equationOfCenter
        let ascendingNode = 125.04 - 1_934.136 * century
        let apparentLongitude = trueLongitude
            - 0.00569
            - 0.00478 * sin(AstronomyMath.radians(ascendingNode))
        let meanObliquity = 23 + (
            26 + (
                21.448
                    - century * (
                        46.815 + century * (0.00059 - century * 0.001813)
                    )
            ) / 60
        ) / 60
        let obliquity = meanObliquity
            + 0.00256 * cos(AstronomyMath.radians(ascendingNode))

        let longitudeRadians = AstronomyMath.radians(apparentLongitude)
        let obliquityRadians = AstronomyMath.radians(obliquity)
        let rightAscension = atan2(
            cos(obliquityRadians) * sin(longitudeRadians),
            cos(longitudeRadians)
        )
        let declination = asin(
            sin(obliquityRadians) * sin(longitudeRadians)
        )

        return Self(rightAscension: rightAscension, declination: declination)
    }
}

fileprivate struct LunarPosition: Sendable {
    private static let earthEquatorialRadiusKilometers = 6_378.137
    private static let moonRadiusKilometers = 1_737.4
    private static let standardRefractionDegrees = 34.0 / 60.0

    let centerAltitude: Double
    let apparentUpperLimbAltitude: Double

    static func calculate(
        at day: JulianDay,
        coordinate: CLLocationCoordinate2D
    ) -> Self {
        let vector = geocentricEquatorialVector(at: day)
        let topocentric = topocentricHorizontalVector(
            vector,
            at: day,
            coordinate: coordinate
        )
        let centerAltitude = AstronomyMath.degrees(
            atan2(topocentric.up, hypot(topocentric.east, topocentric.north))
        )
        let distance = sqrt(
            topocentric.east * topocentric.east
                + topocentric.north * topocentric.north
                + topocentric.up * topocentric.up
        )
        let semidiameter = AstronomyMath.degrees(
            asin(
                (moonRadiusKilometers / earthEquatorialRadiusKilometers)
                    / distance
            )
        )

        return Self(
            centerAltitude: centerAltitude,
            apparentUpperLimbAltitude: centerAltitude
                + semidiameter
                + standardRefractionDegrees
        )
    }

    private static func geocentricEquatorialVector(
        at day: JulianDay
    ) -> CartesianVector {
        // Paul Schlyter's modern-era low-precision lunar model: osculating
        // elements followed by the 12 longitude, 5 latitude, and 2 distance
        // perturbation terms. Coordinates are Earth equatorial radii.
        let days = day.value - 2_451_543.5
        let ascendingNode = AstronomyMath.normalizedDegrees(
            125.1228 - 0.0529538083 * days
        )
        let inclination = 5.1454
        let argumentOfPerigee = AstronomyMath.normalizedDegrees(
            318.0634 + 0.1643573223 * days
        )
        let semiMajorAxis = 60.2666
        let eccentricity = 0.0549
        let meanAnomaly = AstronomyMath.normalizedDegrees(
            115.3654 + 13.0649929509 * days
        )
        let eccentricAnomaly = AstronomyMath.solveKepler(
            meanAnomalyDegrees: meanAnomaly,
            eccentricity: eccentricity
        )
        let orbitalX = semiMajorAxis * (cos(eccentricAnomaly) - eccentricity)
        let orbitalY = semiMajorAxis
            * sqrt(1 - eccentricity * eccentricity)
            * sin(eccentricAnomaly)
        let trueAnomaly = atan2(orbitalY, orbitalX)
        var distance = hypot(orbitalX, orbitalY)

        let node = AstronomyMath.radians(ascendingNode)
        let orbitAngle = trueAnomaly + AstronomyMath.radians(argumentOfPerigee)
        let inclinationRadians = AstronomyMath.radians(inclination)
        let eclipticX = distance * (
            cos(node) * cos(orbitAngle)
                - sin(node) * sin(orbitAngle) * cos(inclinationRadians)
        )
        let eclipticY = distance * (
            sin(node) * cos(orbitAngle)
                + cos(node) * sin(orbitAngle) * cos(inclinationRadians)
        )
        let eclipticZ = distance * sin(orbitAngle) * sin(inclinationRadians)
        var longitude = AstronomyMath.normalizedDegrees(
            AstronomyMath.degrees(atan2(eclipticY, eclipticX))
        )
        var latitude = AstronomyMath.degrees(
            atan2(eclipticZ, hypot(eclipticX, eclipticY))
        )

        let solarArgumentOfPerihelion = AstronomyMath.normalizedDegrees(
            282.9404 + 0.0000470935 * days
        )
        let solarMeanAnomaly = AstronomyMath.normalizedDegrees(
            356.0470 + 0.9856002585 * days
        )
        let solarMeanLongitude = AstronomyMath.normalizedDegrees(
            solarMeanAnomaly + solarArgumentOfPerihelion
        )
        let lunarMeanLongitude = AstronomyMath.normalizedDegrees(
            ascendingNode + argumentOfPerigee + meanAnomaly
        )
        let elongation = AstronomyMath.normalizedDegrees(
            lunarMeanLongitude - solarMeanLongitude
        )
        let argumentOfLatitude = AstronomyMath.normalizedDegrees(
            lunarMeanLongitude - ascendingNode
        )

        longitude +=
            -1.274 * AstronomyMath.sineDegrees(meanAnomaly - 2 * elongation)
            + 0.658 * AstronomyMath.sineDegrees(2 * elongation)
            - 0.186 * AstronomyMath.sineDegrees(solarMeanAnomaly)
            - 0.059 * AstronomyMath.sineDegrees(2 * meanAnomaly - 2 * elongation)
            - 0.057 * AstronomyMath.sineDegrees(
                meanAnomaly - 2 * elongation + solarMeanAnomaly
            )
            + 0.053 * AstronomyMath.sineDegrees(meanAnomaly + 2 * elongation)
            + 0.046 * AstronomyMath.sineDegrees(2 * elongation - solarMeanAnomaly)
            + 0.041 * AstronomyMath.sineDegrees(meanAnomaly - solarMeanAnomaly)
            - 0.035 * AstronomyMath.sineDegrees(elongation)
            - 0.031 * AstronomyMath.sineDegrees(meanAnomaly + solarMeanAnomaly)
            - 0.015 * AstronomyMath.sineDegrees(
                2 * argumentOfLatitude - 2 * elongation
            )
            + 0.011 * AstronomyMath.sineDegrees(meanAnomaly - 4 * elongation)

        latitude +=
            -0.173 * AstronomyMath.sineDegrees(argumentOfLatitude - 2 * elongation)
            - 0.055 * AstronomyMath.sineDegrees(
                meanAnomaly - argumentOfLatitude - 2 * elongation
            )
            - 0.046 * AstronomyMath.sineDegrees(
                meanAnomaly + argumentOfLatitude - 2 * elongation
            )
            + 0.033 * AstronomyMath.sineDegrees(argumentOfLatitude + 2 * elongation)
            + 0.017 * AstronomyMath.sineDegrees(2 * meanAnomaly + argumentOfLatitude)

        distance +=
            -0.58 * AstronomyMath.cosineDegrees(meanAnomaly - 2 * elongation)
            - 0.46 * AstronomyMath.cosineDegrees(2 * elongation)

        let longitudeRadians = AstronomyMath.radians(longitude)
        let latitudeRadians = AstronomyMath.radians(latitude)
        let correctedEclipticX = distance * cos(latitudeRadians) * cos(longitudeRadians)
        let correctedEclipticY = distance * cos(latitudeRadians) * sin(longitudeRadians)
        let correctedEclipticZ = distance * sin(latitudeRadians)
        let obliquity = AstronomyMath.radians(
            23.4393 - 0.0000003563 * days
        )

        return CartesianVector(
            x: correctedEclipticX,
            y: correctedEclipticY * cos(obliquity)
                - correctedEclipticZ * sin(obliquity),
            z: correctedEclipticY * sin(obliquity)
                + correctedEclipticZ * cos(obliquity)
        )
    }

    private static func topocentricHorizontalVector(
        _ moon: CartesianVector,
        at day: JulianDay,
        coordinate: CLLocationCoordinate2D
    ) -> HorizontalVector {
        // WGS 84 geodetic observer at sea level, in Earth equatorial radii.
        let flattening = 1 / 298.257223563
        let eccentricitySquared = flattening * (2 - flattening)
        let latitude = AstronomyMath.radians(coordinate.latitude)
        let localSiderealAngle = AstronomyMath.radians(
            AstronomyMath.greenwichMeanSiderealDegrees(day)
                + coordinate.longitude
        )
        let primeVerticalRadius = 1 / sqrt(
            1 - eccentricitySquared * pow(sin(latitude), 2)
        )
        let observer = CartesianVector(
            x: primeVerticalRadius * cos(latitude) * cos(localSiderealAngle),
            y: primeVerticalRadius * cos(latitude) * sin(localSiderealAngle),
            z: (1 - eccentricitySquared)
                * primeVerticalRadius
                * sin(latitude)
        )
        let relative = CartesianVector(
            x: moon.x - observer.x,
            y: moon.y - observer.y,
            z: moon.z - observer.z
        )
        let east = -sin(localSiderealAngle) * relative.x
            + cos(localSiderealAngle) * relative.y
        let north = -sin(latitude) * cos(localSiderealAngle) * relative.x
            - sin(latitude) * sin(localSiderealAngle) * relative.y
            + cos(latitude) * relative.z
        let up = cos(latitude) * cos(localSiderealAngle) * relative.x
            + cos(latitude) * sin(localSiderealAngle) * relative.y
            + sin(latitude) * relative.z

        return HorizontalVector(east: east, north: north, up: up)
    }
}

fileprivate struct CartesianVector: Sendable {
    let x: Double
    let y: Double
    let z: Double
}

fileprivate struct HorizontalVector: Sendable {
    let east: Double
    let north: Double
    let up: Double
}

fileprivate enum AstronomyMath {
    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    static func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 {
            result += 360
        }
        return result
    }

    static func sineDegrees(_ value: Double) -> Double {
        sin(radians(value))
    }

    static func cosineDegrees(_ value: Double) -> Double {
        cos(radians(value))
    }

    static func solveKepler(
        meanAnomalyDegrees: Double,
        eccentricity: Double
    ) -> Double {
        let meanAnomaly = radians(meanAnomalyDegrees)
        var eccentricAnomaly = meanAnomaly
            + eccentricity * sin(meanAnomaly)
                * (1 + eccentricity * cos(meanAnomaly))

        for _ in 0..<10 {
            let next = eccentricAnomaly - (
                eccentricAnomaly
                    - eccentricity * sin(eccentricAnomaly)
                    - meanAnomaly
            ) / (1 - eccentricity * cos(eccentricAnomaly))
            if abs(next - eccentricAnomaly) < 1e-12 {
                return next
            }
            eccentricAnomaly = next
        }
        return eccentricAnomaly
    }

    static func greenwichMeanSiderealDegrees(_ day: JulianDay) -> Double {
        let centuries = (day.value - 2_451_545) / 36_525
        return normalizedDegrees(
            280.46061837
                + 360.98564736629 * (day.value - 2_451_545)
                + 0.000387933 * centuries * centuries
                - centuries * centuries * centuries / 38_710_000
        )
    }

    static func altitude(
        rightAscension: Double,
        declination: Double,
        at day: JulianDay,
        coordinate: CLLocationCoordinate2D
    ) -> Double {
        let latitude = radians(coordinate.latitude)
        let localSiderealAngle = radians(
            greenwichMeanSiderealDegrees(day) + coordinate.longitude
        )
        let hourAngle = localSiderealAngle - rightAscension
        let sineAltitude =
            sin(latitude) * sin(declination)
            + cos(latitude) * cos(declination) * cos(hourAngle)
        return degrees(asin(min(max(sineAltitude, -1), 1)))
    }
}
