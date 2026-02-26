// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import Foundation

// MARK: - Predict (JSONL cost estimation)

extension UsageViewModel {

    func fetchPredict() {
        let ts = self.tokenSync
        Task.detached { [weak self] in
            let dirs = Self.claudeProjectsDirectories()
            guard !dirs.isEmpty else {
                await MainActor.run {
                    self?.predictFiveHourCost = nil
                    self?.predictSevenDayCost = nil
                    self?.snapshotWriter.updatePredict(fiveHourCost: nil, sevenDayCost: nil)
                    self?.widgetReloader.reloadAllTimelines()
                }
                return
            }
            ts.sync(directories: dirs)
            let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
            let allRecords = ts.loadRecords(since: cutoff)

            let now = Date()
            let fiveH = CostEstimator.estimate(records: allRecords, windowHours: 5, now: now)
            let sevenD = CostEstimator.estimate(records: allRecords, windowHours: 168, now: now)

            await MainActor.run {
                self?.predictFiveHourCost = fiveH.totalCost > 0 ? fiveH.totalCost : nil
                self?.predictSevenDayCost = sevenD.totalCost > 0 ? sevenD.totalCost : nil
                self?.snapshotWriter.updatePredict(
                    fiveHourCost: self?.predictFiveHourCost,
                    sevenDayCost: self?.predictSevenDayCost
                )
                self?.widgetReloader.reloadAllTimelines()
            }
        }
    }

    nonisolated static func claudeProjectsDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeProjects = home.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: claudeProjects.path) else {
            return []
        }
        return [claudeProjects]
    }
}
