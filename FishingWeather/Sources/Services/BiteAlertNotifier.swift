import UserNotifications

/// Delivers the smart bite alerts computed by `BiteAlertScheduler` as local
/// notifications. Each alert is scheduled under its stable id, and prior bite
/// alerts are cleared first — so re-planning replaces the pending set rather
/// than stacking duplicates. Leaves other notifications (e.g. the single
/// next-window reminder) untouched by matching only the `bite-` id prefix.
enum BiteAlertNotifier {
    private static let operations = WeatherDerivedNotificationOperationQueue.shared

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Replaces the pending bite alerts with `alerts`. Always clears the prior
    /// set first (so disabling alerts — an empty list — removes them), then
    /// schedules the new ones if notifications are authorized.
    static func reschedule(
        _ alerts: [BiteAlert],
        provenance: WeatherProvenance,
        scopeKey: String
    ) async {
        await operations.perform {
            let center = UNUserNotificationCenter.current()
            await clearBiteAlerts(center)
            guard !Self.alertsEligibleForCommit(
                alerts,
                provenance: provenance,
                at: .now
            ).isEmpty else { return }
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }
            guard !Task.isCancelled else {
                await removeAllWeatherDerivedNotifications(from: center)
                return
            }
            guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                await removeAllWeatherDerivedNotifications(from: center)
                return
            }

            for alert in alerts {
                guard !Task.isCancelled else {
                    await removeAllWeatherDerivedNotifications(from: center)
                    return
                }
                guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                    await removeAllWeatherDerivedNotifications(from: center)
                    return
                }
                let commitDate = Date.now
                guard WeatherDerivedNotificationPolicy.allows(
                    provenance,
                    at: commitDate
                ) else {
                    await removeAllWeatherDerivedNotifications(from: center)
                    return
                }
                guard WeatherDerivedNotificationPolicy.allows(
                    fireDate: alert.fireDate,
                    from: provenance,
                    at: commitDate
                ) else { continue }

                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: alert.fireDate)
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: alert.id,
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)

                let postCommitDate = Date.now
                guard WeatherDerivedNotificationScope.isActive(scopeKey) else {
                    await removeAllWeatherDerivedNotifications(from: center)
                    return
                }
                if !WeatherDerivedNotificationPolicy.allows(
                    fireDate: alert.fireDate,
                    from: provenance,
                    at: postCommitDate
                ) {
                    center.removePendingNotificationRequests(
                        withIdentifiers: [alert.id]
                    )
                    if !WeatherDerivedNotificationPolicy.allows(
                        provenance,
                        at: postCommitDate
                    ) {
                        await removeAllWeatherDerivedNotifications(from: center)
                        return
                    }
                }
            }
        }
    }

    static func alertsEligibleForCommit(
        _ alerts: [BiteAlert],
        provenance: WeatherProvenance,
        at date: Date
    ) -> [BiteAlert] {
        alerts.filter {
            WeatherDerivedNotificationPolicy.allows(
                fireDate: $0.fireDate,
                from: provenance,
                at: date
            )
        }
    }

    /// Removes every pending bite alert, leaving other app notifications intact.
    static func clearBiteAlerts(_ center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter {
            $0.hasPrefix(WeatherDerivedNotificationIdentifiers.smartAlertPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Invalid, expired, or failed forecast state revokes both the automatic
    /// alert family and the one-off manual next-window reminder.
    static func clearAllWeatherDerivedNotifications() async {
        await operations.perform {
            await removeAllWeatherDerivedNotifications(
                from: UNUserNotificationCenter.current()
            )
        }
    }


    static func clearNextWindowReminder() async {
        await operations.perform {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [WeatherDerivedNotificationIdentifiers.nextWindow]
            )
        }
    }
}

func removeAllWeatherDerivedNotifications(
    from center: UNUserNotificationCenter
) async {
    let pending = await center.pendingNotificationRequests()
    let ids = pending.map(\.identifier).filter(
        WeatherDerivedNotificationIdentifiers.contains
    )
    center.removePendingNotificationRequests(withIdentifiers: ids)
}

/// A tiny asynchronous mutex keeps authorization prompts, clears, and adds in
/// one ordered operation. Without this, a slower authorization result could
/// add an obsolete batch after a newer clear/reschedule call completed.
actor WeatherDerivedNotificationOperationQueue {
    static let shared = WeatherDerivedNotificationOperationQueue()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async -> Result
    ) async -> Result {
        await acquire()
        let result = await operation()
        release()
        return result
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
