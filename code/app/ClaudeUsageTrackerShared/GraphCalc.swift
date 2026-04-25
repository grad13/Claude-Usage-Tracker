// meta: updated=2026-04-25 05:00 checked=-
import Foundation

/// Pure computation helpers for graph coordinate calculations.
/// Used by both WidgetMiniGraph and tests.
public enum GraphCalc {

    /// Resolve the window start date for a graph.
    /// Priority: 1) explicit startedAt (session-scoped), 2) resetsAt - windowSeconds
    ///           (fixed-window fallback), 3) first history timestamp, 4) nil
    public static func resolveWindowStart(
        resetsAt: Date?,
        windowSeconds: TimeInterval,
        history: [HistoryPoint],
        startedAt: Date? = nil
    ) -> Date? {
        if let startedAt {
            return startedAt
        }
        if let resetsAt {
            return resetsAt.addingTimeInterval(-windowSeconds)
        } else if let first = history.first {
            return first.timestamp
        }
        return nil
    }

    /// Number of tick divisions: 5 for <=5h window, 7 for larger.
    public static func tickDivisions(windowSeconds: TimeInterval) -> Int {
        windowSeconds <= 5 * 3600 + 1 ? 5 : 7
    }

    /// Build normalized (0..1) point fractions from history data.
    public static func buildPointFractions(
        history: [HistoryPoint],
        windowStart: Date,
        windowSeconds: TimeInterval
    ) -> [(xFrac: Double, yFrac: Double)] {
        var result: [(xFrac: Double, yFrac: Double)] = []
        for dp in history {
            let elapsed = dp.timestamp.timeIntervalSince(windowStart)
            guard elapsed >= 0 else { continue }
            let xFrac = min(elapsed / windowSeconds, 1.0)
            let yFrac = min(dp.percent / 100.0, 1.0)
            result.append((xFrac: xFrac, yFrac: yFrac))
        }
        return result
    }

    /// Calculate now-position as a fraction (0..1) within the window.
    /// When `startedAt` is provided, windowStart = startedAt (session-scoped).
    /// Otherwise windowStart = resetsAt - windowSeconds (legacy fixed-window).
    public static func nowXFraction(
        resetsAt: Date,
        windowSeconds: TimeInterval,
        startedAt: Date? = nil,
        now: Date = Date()
    ) -> Double {
        let windowStart = startedAt ?? resetsAt.addingTimeInterval(-windowSeconds)
        let nowElapsed = now.timeIntervalSince(windowStart)
        return min(max(nowElapsed / windowSeconds, 0.0), 1.0)
    }

    /// Add "in " prefix to remaining text, except for "expired".
    public static func remainingTextWithPrefix(_ text: String) -> String {
        text == "expired" ? text : "in " + text
    }
}
