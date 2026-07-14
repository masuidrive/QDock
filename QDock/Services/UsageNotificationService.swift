import Foundation
import UserNotifications

/// Posts threshold notifications (70% warning, 90% critical) per quota window.
///
/// Each window instance — identified by provider, window id, and reset time —
/// notifies at most once per threshold, so a window that keeps climbing fires
/// twice total (70 then 90) and a new window after reset starts clean.
@MainActor
final class UsageNotificationService {
    var isEnabled = true

    private struct WindowKey: Hashable {
        let providerId: String
        let windowId: String
        /// Reset timestamp bucketed to the second; a changed reset time
        /// means a new window instance and re-arms the thresholds.
        let resetBucket: Int
    }

    private struct Thresholds {
        static let warning = 70.0
        static let critical = 90.0
    }

    private var notifiedWarning: Set<WindowKey> = []
    private var notifiedCritical: Set<WindowKey> = []
    private var lastNotificationAt: Date?
    /// Global floor between notifications so a burst of providers/windows
    /// crossing at once can't spam more than one banner every few seconds.
    private let minimumNotificationSpacing: TimeInterval = 5

    func evaluate(_ quotaByProvider: [String: QuotaData]) {
        guard isEnabled else { return }

        for (providerId, quota) in quotaByProvider {
            // Never alert off stale cached data.
            guard !quota.isStale else { continue }

            for window in quota.windows {
                let key = WindowKey(
                    providerId: providerId,
                    windowId: window.id,
                    resetBucket: Int(window.resetsAt?.timeIntervalSince1970 ?? 0)
                )

                if window.usagePercent >= Thresholds.critical {
                    if !notifiedCritical.contains(key) {
                        notifiedCritical.insert(key)
                        notifiedWarning.insert(key) // don't follow up with the weaker alert
                        post(provider: quota.provider, window: window, critical: true)
                    }
                } else if window.usagePercent >= Thresholds.warning {
                    if !notifiedWarning.contains(key) {
                        notifiedWarning.insert(key)
                        post(provider: quota.provider, window: window, critical: false)
                    }
                } else {
                    // Dropped back below the warning line (e.g. limit raise):
                    // re-arm so a later climb notifies again.
                    notifiedWarning.remove(key)
                    notifiedCritical.remove(key)
                }
            }
        }

        pruneStaleKeys(currentProviders: quotaByProvider)
    }

    private func post(provider: String, window: QuotaWindow, critical: Bool) {
        if let last = lastNotificationAt,
           Date().timeIntervalSince(last) < minimumNotificationSpacing {
            return
        }
        lastNotificationAt = Date()

        let content = UNMutableNotificationContent()
        content.title = critical
            ? "\(provider): \(window.displayName) almost exhausted"
            : "\(provider): \(window.displayName) usage high"
        var body = "\(Int(window.usagePercent))% of the \(window.displayName.lowercased()) limit used."
        if let countdown = window.resetCountdown {
            body += " Resets in \(countdown)."
        }
        content.body = body
        content.sound = critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: "qdock-usage-\(provider)-\(window.id)-\(critical ? "critical" : "warning")",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Keep the memory bounded: drop keys for windows that no longer exist.
    private func pruneStaleKeys(currentProviders: [String: QuotaData]) {
        var liveKeys: Set<WindowKey> = []
        for (providerId, quota) in currentProviders {
            for window in quota.windows {
                liveKeys.insert(WindowKey(
                    providerId: providerId,
                    windowId: window.id,
                    resetBucket: Int(window.resetsAt?.timeIntervalSince1970 ?? 0)
                ))
            }
        }
        notifiedWarning.formIntersection(liveKeys)
        notifiedCritical.formIntersection(liveKeys)
    }
}
