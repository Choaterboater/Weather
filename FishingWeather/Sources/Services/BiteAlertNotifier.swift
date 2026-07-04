import UserNotifications

/// Delivers the smart bite alerts computed by `BiteAlertScheduler` as local
/// notifications. Each alert is scheduled under its stable id, and prior bite
/// alerts are cleared first — so re-planning replaces the pending set rather
/// than stacking duplicates. Leaves other notifications (e.g. the single
/// next-window reminder) untouched by matching only the `bite-` id prefix.
enum BiteAlertNotifier {
    private static let idPrefix = "bite-"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Replaces the pending bite alerts with `alerts`. Always clears the prior
    /// set first (so disabling alerts — an empty list — removes them), then
    /// schedules the new ones if notifications are authorized.
    static func reschedule(_ alerts: [BiteAlert]) async {
        let center = UNUserNotificationCenter.current()
        await clearBiteAlerts(center)
        guard !alerts.isEmpty, await requestAuthorization() else { return }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Removes every pending bite alert, leaving other app notifications intact.
    static func clearBiteAlerts(_ center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
