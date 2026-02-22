import XCTest
@testable import QLaunch

final class LaunchpadCoreTests: XCTestCase {
    func testNormalizeQueryTrimsAndLowercases() {
        XCTAssertEqual(LaunchpadCore.normalizeQuery("  SAFARI  "), "safari")
        XCTAssertEqual(LaunchpadCore.normalizeQuery(""), "")
    }

    func testFilterAppsIsCaseInsensitive() {
        let apps = [
            app(name: "Safari", bundleID: "com.apple.Safari"),
            app(name: "系统设置", bundleID: "com.apple.SystemSettings"),
            app(name: "Photos", bundleID: "com.apple.Photos"),
        ]

        XCTAssertEqual(LaunchpadCore.filter(apps: apps, query: "saf").map(\.name), ["Safari"])
        XCTAssertEqual(LaunchpadCore.filter(apps: apps, query: "SAFARI").map(\.name), ["Safari"])
        XCTAssertEqual(LaunchpadCore.filter(apps: apps, query: "系统").map(\.name), ["系统设置"])
        XCTAssertEqual(LaunchpadCore.filter(apps: apps, query: ""), apps)
    }

    func testFilterAppsSupportsCaseInsensitiveFuzzySearch() {
        let apps = [
            app(name: "Safari", bundleID: "com.apple.Safari"),
            app(name: "Spotify", bundleID: "com.spotify.client"),
        ]

        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "SFR").map(\.name),
            ["Safari"]
        )
        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "sptfy").map(\.name),
            ["Spotify"]
        )
    }

    func testFilterAppsSupportsBundleIDSearch() {
        let apps = [
            app(name: "Safari", bundleID: "com.apple.Safari"),
            app(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        ]

        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "googlecode").map(\.name),
            ["iTerm"]
        )
    }

    func testFilterAppsSupportsPinyinSearchForChineseName() {
        let apps = [
            app(name: "微信开发者工具", bundleID: "com.tencent.wechat.devtools"),
            app(name: "系统设置", bundleID: "com.apple.SystemSettings"),
        ]

        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "weixin").map(\.name),
            ["微信开发者工具"]
        )

        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "wei xin kai fa").map(\.name),
            ["微信开发者工具"]
        )

        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "weixinkaifa").map(\.name),
            ["微信开发者工具"]
        )
        XCTAssertEqual(
            LaunchpadCore.filter(apps: apps, query: "WXKF").map(\.name),
            ["微信开发者工具"]
        )
    }

    func testPageSizeThresholds() {
        XCTAssertEqual(LaunchpadCore.pageSize(for: CGSize(width: 500, height: 800)), 35)
        XCTAssertEqual(LaunchpadCore.pageSize(for: CGSize(width: 860, height: 820)), 35)
        XCTAssertEqual(LaunchpadCore.pageSize(for: CGSize(width: 1200, height: 900)), 35)
        XCTAssertEqual(LaunchpadCore.pageSize(for: CGSize(width: 1400, height: 900)), 35)
    }

    func testClampKeepsPageInBounds() {
        XCTAssertEqual(LaunchpadCore.clamp(page: -2, totalPages: 3), 0)
        XCTAssertEqual(LaunchpadCore.clamp(page: 1, totalPages: 3), 1)
        XCTAssertEqual(LaunchpadCore.clamp(page: 99, totalPages: 3), 2)
        XCTAssertEqual(LaunchpadCore.clamp(page: 0, totalPages: 0), 0)
    }

    func testPaginateReturnsClampedPageAndSlice() {
        let apps = (0..<11).map { app(name: "App-\($0)", bundleID: "com.example.app\($0)") }

        let page1 = LaunchpadCore.paginate(apps: apps, page: 1, pageSize: 5)
        XCTAssertEqual(page1.totalPages, 3)
        XCTAssertEqual(page1.page, 1)
        XCTAssertEqual(page1.items.count, 5)
        XCTAssertEqual(page1.items.first?.name, apps[5].name)

        let overflow = LaunchpadCore.paginate(apps: apps, page: 5, pageSize: 5)
        XCTAssertEqual(overflow.page, 2)
        XCTAssertEqual(overflow.items.count, 1)
        XCTAssertEqual(overflow.items.first?.name, apps[10].name)
    }

    func testPaginateEmptyAppsKeepsSinglePage() {
        let pagination = LaunchpadCore.paginate(apps: [], page: 7, pageSize: 10)

        XCTAssertEqual(pagination.totalPages, 1)
        XCTAssertEqual(pagination.page, 0)
        XCTAssertTrue(pagination.items.isEmpty)
    }

    private func app(name: String, bundleID: String?) -> LaunchpadApp {
        LaunchpadApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            name: name,
            bundleIdentifier: bundleID
        )
    }
}
