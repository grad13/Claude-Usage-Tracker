// meta: created=2026-02-26 updated=2026-02-27 checked=2026-02-26
import Foundation
import ServiceManagement

// MARK: - Settings

extension UsageViewModel {

    func setRefreshInterval(minutes: Int) {
        settings.refreshIntervalMinutes = minutes
        settingsStore.save(settings)
        restartAutoRefresh()
    }

    func toggleStartAtLogin() {
        settings.startAtLogin.toggle()
        settingsStore.save(settings)
        syncLoginItem()
    }

    func setShowHourlyGraph(_ show: Bool) {
        settings.showHourlyGraph = show
        settingsStore.save(settings)
    }

    func setShowWeeklyGraph(_ show: Bool) {
        settings.showWeeklyGraph = show
        settingsStore.save(settings)
    }

    func setChartWidth(_ width: Int) {
        settings.chartWidth = width
        settingsStore.save(settings)
    }

    func setHourlyColorPreset(_ preset: ChartColorPreset) {
        settings.hourlyColorPreset = preset
        settingsStore.save(settings)
    }

    func setWeeklyColorPreset(_ preset: ChartColorPreset) {
        settings.weeklyColorPreset = preset
        settingsStore.save(settings)
    }

    // MARK: - Alert Settings

    func setWeeklyAlertEnabled(_ enabled: Bool) {
        settings.weeklyAlertEnabled = enabled
        settingsStore.save(settings)
    }

    func setWeeklyAlertThreshold(_ threshold: Int) {
        settings.weeklyAlertThreshold = threshold
        settingsStore.save(settings)
    }

    func setHourlyAlertEnabled(_ enabled: Bool) {
        settings.hourlyAlertEnabled = enabled
        settingsStore.save(settings)
    }

    func setHourlyAlertThreshold(_ threshold: Int) {
        settings.hourlyAlertThreshold = threshold
        settingsStore.save(settings)
    }

    func setDailyAlertEnabled(_ enabled: Bool) {
        settings.dailyAlertEnabled = enabled
        settingsStore.save(settings)
    }

    func setDailyAlertThreshold(_ threshold: Int) {
        settings.dailyAlertThreshold = threshold
        settingsStore.save(settings)
    }

    func setDailyAlertDefinition(_ definition: DailyAlertDefinition) {
        settings.dailyAlertDefinition = definition
        settingsStore.save(settings)
    }

    // MARK: - Login Item

    func syncLoginItem() {
        do {
            try loginItemManager.setEnabled(settings.startAtLogin)
        } catch {
            // Revert the setting — UI must reflect actual system state.
            settings.startAtLogin.toggle()
            settingsStore.save(settings)
            self.error = "Login item failed: \(error.localizedDescription)"
            debug("syncLoginItem failed: \(error)")
        }
    }
}
