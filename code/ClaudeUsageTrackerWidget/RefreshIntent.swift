// meta: created=2026-03-15 updated=2026-03-15 checked=never
import AppIntents
import WidgetKit

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Usage"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
