import XCTest
@testable import QLaunch

final class HotKeySettingsTests: XCTestCase {
    func testHotKeyConfigurationNormalizesKey() {
        let raw = HotKeyConfiguration(
            key: "  s  ",
            command: true,
            option: false,
            control: true,
            shift: false
        )

        XCTAssertEqual(raw.normalized.key, "S")
        XCTAssertEqual(raw.normalized.displayText, "⌃⌘S")
    }

    func testHotKeySettingsDetectsConflict() {
        let same = HotKeyConfiguration(
            key: "K",
            command: true,
            option: true,
            control: true,
            shift: false
        )

        let settings = HotKeySettings(
            launchpad: same,
            spotlight: same
        )

        XCTAssertTrue(settings.hasConflict)
    }

    func testHotKeySettingsDefaultsHaveNoConflict() {
        XCTAssertFalse(HotKeySettings.defaultValue.hasConflict)
    }
}
