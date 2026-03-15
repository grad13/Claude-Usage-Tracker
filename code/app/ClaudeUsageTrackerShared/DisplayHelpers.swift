// meta: created=2026-02-22 updated=2026-03-04 checked=2026-03-03
import Foundation
import CoreGraphics

public enum DisplayHelpers {

    /// Format remaining time until a date.
    /// - "3d 5h" for >= 24h
    /// - "2h 15m" for >= 1h
    /// - "19m" for < 1h (omits "0h")
    /// - "expired" for past dates
    public static func remainingText(until date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "expired" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    /// Whether percent text should render below the marker (true) or above (false).
    /// Show below only when usage exceeds 80% (marker near top edge); otherwise above.
    public static func percentTextShowsBelow(percent: Double) -> Bool {
        percent > 80
    }

    /// Horizontal anchor for percent text (0 = leading, 0.5 = center, 1 = trailing).
    /// Shifts anchor when marker is near left or right edge to prevent clipping.
    public static func percentTextAnchorX(
        markerX: CGFloat,
        graphWidth: CGFloat,
        margin: CGFloat = 16
    ) -> CGFloat {
        if markerX < margin { return 0 }
        if markerX > graphWidth - margin { return 1 }
        return 0.5
    }
}
