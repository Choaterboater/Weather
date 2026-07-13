import Foundation

struct LocationDescriptor: Equatable, Sendable {
    let city: String?
    let stateCode: String?
    let featureName: String?
    let displayName: String
    let subtitle: String?

    static func make(city: String?, stateCode: String?, featureName: String?) -> Self {
        let city = clean(city)
        let state = clean(stateCode)?.uppercased()
        let feature = clean(featureName).flatMap { coordinateLike($0) ? nil : $0 }

        if let city {
            return Self(
                city: city,
                stateCode: state,
                featureName: feature,
                displayName: state.map { "\(city), \($0)" } ?? city,
                subtitle: feature == city ? nil : feature
            )
        }
        if let feature {
            return Self(
                city: nil,
                stateCode: state,
                featureName: feature,
                displayName: feature,
                subtitle: state
            )
        }
        return Self(
            city: nil,
            stateCode: state,
            featureName: nil,
            displayName: "Current Location",
            subtitle: state
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func coordinateLike(_ value: String) -> Bool {
        if value.contains("°") && value.contains(",") { return true }
        let parts = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts.count == 2 && parts.allSatisfy { Double($0) != nil }
    }
}
