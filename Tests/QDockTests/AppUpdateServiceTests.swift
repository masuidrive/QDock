import XCTest
@testable import QDock

final class AppUpdateServiceTests: XCTestCase {

    // MARK: - hdiutil attach output parsing

    func testParseMountPointFromTypicalAttachOutput() {
        let output = """
        /dev/disk4          \tGUID_partition_scheme          \t
        /dev/disk4s1        \tApple_HFS                      \t/Volumes/QDock 0.3.0
        """
        XCTAssertEqual(
            AppUpdateService.parseMountPoint(from: output),
            "/Volumes/QDock 0.3.0"
        )
    }

    func testParseMountPointReturnsNilWithoutVolumesLine() {
        let output = "/dev/disk4\tGUID_partition_scheme\t"
        XCTAssertNil(AppUpdateService.parseMountPoint(from: output))
    }

    // MARK: - checksums.txt parsing

    func testExpectedChecksumMatchesTwoSpaceFormat() {
        let content = """
        0a1b2c3d4e5f  QDock-0.3.0.dmg
        ffffffffffff  Other.dmg
        """
        XCTAssertEqual(
            AppUpdateService.expectedChecksum(in: content, for: "QDock-0.3.0.dmg"),
            "0a1b2c3d4e5f"
        )
    }

    func testExpectedChecksumMatchesBinaryStarFormat() {
        let content = "ABCDEF012345 *QDock-0.3.0.dmg"
        XCTAssertEqual(
            AppUpdateService.expectedChecksum(in: content, for: "QDock-0.3.0.dmg"),
            "abcdef012345"
        )
    }

    func testExpectedChecksumIgnoresPartialNameMatches() {
        let content = "0a1b2c3d4e5f  Not-QDock-0.3.0.dmg"
        XCTAssertNil(AppUpdateService.expectedChecksum(in: content, for: "QDock-0.3.0.dmg"))
    }

    // MARK: - checksum verification

    func testVerifyChecksumPassesAndFailsOnRealFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qdock-checksum-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = dir.appendingPathComponent("artifact.bin")
        try Data("hello qdock".utf8).write(to: artifact)

        // shasum -a 256 of "hello qdock"
        let goodChecksum = "4e1a9f76fe56318fdc4dc5a5f123b19837a661bfa21978176434d5c12e646fda"

        let goodFile = dir.appendingPathComponent("checksums.txt")
        try "\(goodChecksum)  artifact.bin\n".write(to: goodFile, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try AppUpdateService.verifyChecksum(of: artifact, against: goodFile))

        let badFile = dir.appendingPathComponent("checksums-bad.txt")
        try "\(String(repeating: "0", count: 64))  artifact.bin\n"
            .write(to: badFile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AppUpdateService.verifyChecksum(of: artifact, against: badFile)) { error in
            guard case AppUpdateError.checksumMismatch = error else {
                return XCTFail("Expected checksumMismatch, got \(error)")
            }
        }
    }

    // MARK: - version normalization

    func testNormalizeVersionStripsVPrefixAndWhitespace() {
        XCTAssertEqual(AppUpdateService.normalizeVersion(" v0.3.0\n"), "0.3.0")
        XCTAssertEqual(AppUpdateService.normalizeVersion("0.3.0"), "0.3.0")
    }

    // MARK: - End-to-end (opt-in: hits GitHub, mounts a DMG)

    /// Full update flow against the real latest release, installed into a
    /// scratch directory. Run with: QDOCK_UPDATE_E2E=1 swift test
    func testInstallLatestReleaseEndToEnd() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QDOCK_UPDATE_E2E"] == "1",
            "Set QDOCK_UPDATE_E2E=1 to run the network/DMG install test"
        )

        let service = AppUpdateService()
        let release = try await service.fetchLatestStableRelease()
        XCTAssertNotNil(release.dmg, "Latest release must ship a DMG asset")
        XCTAssertNotNil(release.checksums, "Latest release must ship checksums.txt")

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("qdock-e2e-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let installedPath = try await service.installRelease(release, into: scratch)

        XCTAssertTrue(FileManager.default.fileExists(atPath: installedPath.path))
        let infoPlist = installedPath.appendingPathComponent("Contents/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: infoPlist))
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, release.version)
    }
}
