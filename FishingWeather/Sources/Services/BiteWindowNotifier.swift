import UserNotifications

/// Schedules a local notification ahead of an upcoming bite window.
enum BiteWindowNotifier {
    static let leadTime: TimeInterval = 30 * 60
    private static let identifier = "biteWindow.next"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Schedules a reminder `leadTime` before the window starts. Returns false if
    /// the lead time has already passed, authorization was denied, or scheduling failed.
    @discardableResult
    static func scheduleReminder(for window: BiteWindow) async -> Bool {
        guard await requestAuthorization() else { return false }

        let fireDate = window.start.addingTimeInterval(-leadTime)
        guard fireDate > .now else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Bite window soon"
        content.body = "\(window.period.rawValue) window (\(window.cause)) starts at "
            + "\(window.start.formatted(date: .omitted, time: .shortened))."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
