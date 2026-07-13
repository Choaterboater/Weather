import UserNotifications

/// Schedules a local notification ahead of an upcoming bite window.
enum BiteWindowNotifier {
    static let leadTime: TimeInterval = 30 * 60

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Schedules a reminder `leadTime` before the window starts. Returns false if
    /// the lead time has already passed, authorization was denied, or scheduling failed.
    @discardableResult
    static func scheduleReminder(
        for window: BiteWindow,
        provenance: WeatherProvenance,
        scopeKey: String,
        now: Date = .now
    ) async -> Bool {
        guard WeatherDerivedNotificationPolicy.allows(
            provenance,
            at: now
        ) else {
            await BiteAlertNotifier.clearAllWeatherDerivedNotifications()
            return false
        }

        let fireDate = window.start.addingTimeInterval(-leadTime)
        guard WeatherDerivedNotificationPolicy.allows(
            fireDate: fireDate,
            from: provenance,
            at: now
        ) else {
            await BiteAlertNotifier.clearNextWindowReminder()
            return false
        }

        return await WeatherDerivedNotificationOperationQueue.shared.perform {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(
                withIdentifiers: [WeatherDerivedNotificationIdentifiers.nextWindow]
            )

            let queuedAt = Date.now
            guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                await removeAllWeatherDerivedNotifications(from: center)
                return false
            }
            guard WeatherDerivedNotificationPolicy.allows(
                provenance,
                at: queuedAt
            ) else {
                await removeAllWeatherDerivedNotifications(from: center)
                return false
            }
            guard WeatherDerivedNotificationPolicy.allows(
                fireDate: fireDate,
                from: provenance,
                at: queuedAt
            ) else { return false }

            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return false }
            guard !Task.isCancelled else {
                await removeAllWeatherDerivedNotifications(from: center)
                return false
            }
            guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                await removeAllWeatherDerivedNotifications(from: center)
                return false
            }

            let commitDate = Date.now
            guard WeatherDerivedNotificationPolicy.allows(
                provenance,
                at: commitDate
            ) else {
                await removeAllWeatherDerivedNotifications(from: center)
                return false
            }
            guard WeatherDerivedNotificationPolicy.allows(
                fireDate: fireDate,
                from: provenance,
                at: commitDate
            ) else { return false }

            let content = UNMutableNotificationContent()
            content.title = "Bite window soon"
            content.body = "\(window.period.rawValue) window (\(window.cause)) starts at "
                + "\(window.start.formatted(date: .omitted, time: .shortened))."
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: WeatherDerivedNotificationIdentifiers.nextWindow,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                    await removeAllWeatherDerivedNotifications(from: center)
                    return false
                }
                guard WeatherDerivedNotificationPolicy.allows(
                    fireDate: fireDate,
                    from: provenance,
                    at: .now
                ) else {
                    center.removePendingNotificationRequests(
                        withIdentifiers: [
                            WeatherDerivedNotificationIdentifiers.nextWindow,
                        ]
                    )
                    return false
                }
                return true
            } catch {
                return false
            }
        }
    }
}
