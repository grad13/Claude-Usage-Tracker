// meta: created=2026-02-26 updated=2026-02-27 checked=2026-02-26
import SwiftUI

// MARK: - Menu Content

struct MenuContent: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let fiveH = viewModel.fiveHourPercent {
            if let remaining = viewModel.fiveHourRemainingText {
                Text("5-hour: \(fiveH, specifier: "%.1f")%  (resets in \(remaining))")
            } else {
                Text("5-hour: \(fiveH, specifier: "%.1f")%")
            }
        }
        if let sevenD = viewModel.sevenDayPercent {
            if let remaining = viewModel.sevenDayRemainingText {
                Text("7-day: \(sevenD, specifier: "%.1f")%  (resets in \(remaining))")
            } else {
                Text("7-day: \(sevenD, specifier: "%.1f")%")
            }
        }
        if let error = viewModel.error {
            Text("Error: \(error)")
                .foregroundColor(.red)
        }

        Divider()

        if viewModel.isLoggedIn {
            Button("Sign Out") {
                viewModel.signOut()
            }
        } else {
            Button {
                openWindow(id: "login")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Sign In...")
                    .foregroundColor(.red)
            }
        }

        Button("Refresh") {
            viewModel.fetch()
        }
        .disabled(viewModel.isFetching)

        Divider()

        Button("Analysis") {
            openWindow(id: "analysis")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Usage Page (Browser)") {
            if let url = URL(string: "https://claude.ai/settings/usage") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Menu("Graph Settings") {
            Toggle("Show 5-hour", isOn: Binding(
                get: { viewModel.settings.showHourlyGraph },
                set: { viewModel.setShowHourlyGraph($0) }
            ))
            Toggle("Show 7-day", isOn: Binding(
                get: { viewModel.settings.showWeeklyGraph },
                set: { viewModel.setShowWeeklyGraph($0) }
            ))

            Divider()

            Menu("Chart Width") {
                let current = viewModel.settings.chartWidth
                ForEach(AppSettings.chartWidthPresets, id: \.self) { width in
                    Button("\(width)pt") {
                        viewModel.setChartWidth(width)
                    }
                    .badge(current == width ? "✓" : "")
                }
            }

            Divider()

            Menu("5-hour Color") {
                ForEach(ChartColorPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        viewModel.setHourlyColorPreset(preset)
                    }
                    .badge(viewModel.settings.hourlyColorPreset == preset ? "✓" : "")
                }
            }
            Menu("7-day Color") {
                ForEach(ChartColorPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        viewModel.setWeeklyColorPreset(preset)
                    }
                    .badge(viewModel.settings.weeklyColorPreset == preset ? "✓" : "")
                }
            }
        }

        Menu("Alert Settings") {
            Toggle("Weekly Alert", isOn: Binding(
                get: { viewModel.settings.weeklyAlertEnabled },
                set: { viewModel.setWeeklyAlertEnabled($0) }
            ))
            if viewModel.settings.weeklyAlertEnabled {
                Menu("Weekly Threshold") {
                    ForEach([10, 20, 30, 50], id: \.self) { threshold in
                        Button("Remaining \(threshold)%") {
                            viewModel.setWeeklyAlertThreshold(threshold)
                        }
                        .badge(viewModel.settings.weeklyAlertThreshold == threshold ? "✓" : "")
                    }
                }
            }

            Toggle("Hourly Alert", isOn: Binding(
                get: { viewModel.settings.hourlyAlertEnabled },
                set: { viewModel.setHourlyAlertEnabled($0) }
            ))
            if viewModel.settings.hourlyAlertEnabled {
                Menu("Hourly Threshold") {
                    ForEach([10, 20, 30, 50], id: \.self) { threshold in
                        Button("Remaining \(threshold)%") {
                            viewModel.setHourlyAlertThreshold(threshold)
                        }
                        .badge(viewModel.settings.hourlyAlertThreshold == threshold ? "✓" : "")
                    }
                }
            }

            Divider()

            Toggle("Daily Alert", isOn: Binding(
                get: { viewModel.settings.dailyAlertEnabled },
                set: { viewModel.setDailyAlertEnabled($0) }
            ))
            if viewModel.settings.dailyAlertEnabled {
                Menu("Daily Threshold") {
                    ForEach([10, 15, 20, 30], id: \.self) { threshold in
                        Button("\(threshold)% per day") {
                            viewModel.setDailyAlertThreshold(threshold)
                        }
                        .badge(viewModel.settings.dailyAlertThreshold == threshold ? "✓" : "")
                    }
                }
                Menu("Day Definition") {
                    Button("Calendar (midnight)") {
                        viewModel.setDailyAlertDefinition(.calendar)
                    }
                    .badge(viewModel.settings.dailyAlertDefinition == .calendar ? "✓" : "")
                    Button("Session-based") {
                        viewModel.setDailyAlertDefinition(.session)
                    }
                    .badge(viewModel.settings.dailyAlertDefinition == .session ? "✓" : "")
                }
            }
        }

        Menu("Refresh Interval") {
            let current = viewModel.settings.refreshIntervalMinutes

            Button("Off") {
                viewModel.setRefreshInterval(minutes: 0)
            }
            .badge(current == 0 ? "✓" : "")

            Divider()

            ForEach(AppSettings.presets, id: \.self) { minutes in
                Button("\(minutes) min") {
                    viewModel.setRefreshInterval(minutes: minutes)
                }
                .badge(current == minutes ? "✓" : "")
            }

            Divider()

            Button("Custom...") {
                promptCustomInterval(current: current) { minutes in
                    viewModel.setRefreshInterval(minutes: minutes)
                }
            }
            if current > 0, !AppSettings.presets.contains(current) {
                Text("Current: \(current) min ✓")
            }
        }

        Toggle("Start at Login", isOn: Binding(
            get: { viewModel.settings.startAtLogin },
            set: { _ in viewModel.toggleStartAtLogin() }
        ))

        Divider()

        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Custom Interval Prompt

private func promptCustomInterval(current: Int, onSet: @escaping (Int) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Custom Refresh Interval"
    alert.informativeText = "Enter interval in minutes (1 or more, 0 to disable):"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    input.stringValue = current > 0 ? "\(current)" : ""
    input.placeholderString = "minutes"
    alert.accessoryView = input

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn, let minutes = Int(input.stringValue), minutes >= 0 {
        onSet(minutes)
    }
}
