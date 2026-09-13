import Foundation

/// Device permissions are app-wide in iOS; permission to import that device's
/// data into a LifeOS account must also be granted by that account.
public enum AccountDeviceAccess {
    public static let calendarKey = "calendar.accountEnabled"

    public static func allowsCalendar(defaults: UserDefaults, systemAuthorized: Bool) -> Bool {
        systemAuthorized && defaults.bool(forKey: calendarKey)
    }
}
