import Foundation
import OSLog

/// Centralized `os.Logger` instances keyed by feature area. Using
/// `Logger` from `OSLog` instead of `print`:
///
/// - Zero-cost when the Console isn't attached (the OS signposts compile away).
/// - Automatically shows up in Console.app, Instruments, and Xcode's debug
///   console — filterable by subsystem and category.
/// - Privacy-aware: values are private by default and redacted unless you
///   opt in with `\(value, privacy: .public)`. We mark only identifiers,
///   HTTP status codes, and non-PII metadata as `.public` so the log is
///   useful in release builds without leaking user data.
enum AppLog {
    /// Reverse-DNS subsystem tag used for all loggers so they can be filtered
    /// as a group in Console.app with `subsystem:vietmind.finosWLb`.
    private static let subsystem = "vietmind.finosWLb"

    /// Sign-in / sign-up / session / token refresh events.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Edge Function invocations, PostgREST queries, Realtime subscribe/unsubscribe.
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Employee check-in/out flow, offline queue, GPS + WiFi reads.
    static let checkin = Logger(subsystem: subsystem, category: "checkin")

    /// SwiftData reads/writes, migrations.
    static let data = Logger(subsystem: subsystem, category: "data")

    /// High-level view lifecycle + navigation events worth tracing.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Biometric unlock + keychain access.
    static let security = Logger(subsystem: subsystem, category: "security")

    /// Local notifications scheduling / delivery.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}

/// Short, stable description of any error suitable for log output. Prefers
/// `LocalizedError.errorDescription`, falls back to the Swift type name +
/// `localizedDescription` so `NSError` domains don't get swallowed.
///
/// Named `logMessage(for:)` (not `describe`) to avoid collisions with the
/// per-view static helpers that format `DecodingError` for user-visible
/// alerts.
func logMessage(for error: Error) -> String {
    if let localized = (error as? LocalizedError)?.errorDescription {
        return localized
    }
    let ns = error as NSError
    return "\(type(of: error)): \(ns.domain)#\(ns.code) \(ns.localizedDescription)"
}
