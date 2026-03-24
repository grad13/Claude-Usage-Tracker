// meta: updated=2026-03-07 15:25 checked=-
import XCTest
@testable import ClaudeUsageTracker

// MARK: - ViewModelTests + TimeProgress

extension ViewModelTests {

    // MARK: - timeProgress

    func testTimeProgress_midWindow() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.4, accuracy: 0.01)
    }

    func testTimeProgress_nil() {
        let progress = UsageViewModel.timeProgress(
            resetsAt: nil, windowSeconds: 5 * 3600
        )
        XCTAssertEqual(progress, 0.0)
    }

    func testTimeProgress_expired() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-100)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0)
    }

    func testTimeProgress_justStarted() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(5 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - timeProgress Clamping

    func testTimeProgress_clampedToZero() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(10 * 3600)
        let progress = UsageViewModel.timeProgress(
            resetsAt: resetsAt, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.01)
    }

    // MARK: - timeProgress Edge Cases

    func testTimeProgress_resetsAtEqualsNow() {
        let now = Date()
        let progress = UsageViewModel.timeProgress(
            resetsAt: now, windowSeconds: 5 * 3600, now: now
        )
        XCTAssertEqual(progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Computed Property: fiveHourTimeProgress / sevenDayTimeProgress

    func testFiveHourTimeProgress_usesResetsAt() {
        let vm = makeVM()
        XCTAssertEqual(vm.fiveHourTimeProgress, 0.0)
        vm.fiveHourResetsAt = Date().addingTimeInterval(3 * 3600)
        XCTAssertEqual(vm.fiveHourTimeProgress, 0.4, accuracy: 0.05)
    }

    func testSevenDayTimeProgress_usesResetsAt() {
        let vm = makeVM()
        XCTAssertEqual(vm.sevenDayTimeProgress, 0.0)
        vm.sevenDayResetsAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        XCTAssertEqual(vm.sevenDayTimeProgress, 0.5, accuracy: 0.05)
    }
}
