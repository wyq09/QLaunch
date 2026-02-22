import XCTest
@testable import QLaunch

final class InstalledAppsProviderTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testLoadInstalledAppsFindsAppsAndSortsByName() throws {
        let root = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try createFakeApp(at: root.appendingPathComponent("Beta.app"), bundleID: "com.example.beta")
        try createFakeApp(at: root.appendingPathComponent("Alpha.app"), bundleID: "com.example.alpha")

        let result = InstalledAppsProvider.loadInstalledApps(searchPaths: [root])

        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["com.example.alpha", "com.example.beta"])
    }

    func testLoadInstalledAppsDeduplicatesByBundleID() throws {
        let rootA = tempRoot.appendingPathComponent("A", isDirectory: true)
        let rootB = tempRoot.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try createFakeApp(at: rootA.appendingPathComponent("First.app"), bundleID: "com.example.same")
        try createFakeApp(at: rootB.appendingPathComponent("Second.app"), bundleID: "com.example.same")

        let result = InstalledAppsProvider.loadInstalledApps(searchPaths: [rootA, rootB])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.bundleIdentifier, "com.example.same")
        XCTAssertEqual(result.first?.name, "First")
    }

    private func createFakeApp(at appURL: URL, bundleID: String) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": appURL.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: plistURL)
    }
}
