import XCTest
@testable import TubeShelfCore

final class CloudDriveLocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDrive(_ account: String, withMyDrive: Bool = true) throws {
        let base = root.appendingPathComponent("GoogleDrive-\(account)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if withMyDrive {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent("My Drive", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    func testFindsAnAccountAndReadsTheAddress() throws {
        try makeDrive("someone@gmail.com")
        let drives = CloudDriveLocator(root: root).googleDrives()
        XCTAssertEqual(drives.count, 1)
        XCTAssertEqual(drives[0].accountName, "someone@gmail.com")
        XCTAssertEqual(drives[0].myDrive.lastPathComponent, "My Drive")
    }

    func testIgnoresFoldersThatAreNotSignedInDrives() throws {
        try makeDrive("not-signed-in@gmail.com", withMyDrive: false)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("iCloud Drive", isDirectory: true),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(CloudDriveLocator(root: root).googleDrives().isEmpty)
    }

    func testMultipleAccountsAreSortedByAddress() throws {
        try makeDrive("zoe@gmail.com")
        try makeDrive("adam@gmail.com")
        let names = CloudDriveLocator(root: root).googleDrives().map(\.accountName)
        XCTAssertEqual(names, ["adam@gmail.com", "zoe@gmail.com"])
    }

    func testMissingCloudStorageFolderIsNotAnError() {
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        XCTAssertTrue(CloudDriveLocator(root: missing).googleDrives().isEmpty)
    }

    func testBackupFolderIsCreatedInsideMyDrive() throws {
        try makeDrive("someone@gmail.com")
        let drive = try XCTUnwrap(CloudDriveLocator(root: root).googleDrives().first)
        let locator = CloudDriveLocator(root: root)

        let folder = try locator.backupFolder(in: drive)
        XCTAssertEqual(folder.lastPathComponent, "TubeShelf Backups")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        // Idempotent: a second call does not fail on an existing folder.
        XCTAssertEqual(try locator.backupFolder(in: drive).path, folder.path)
    }

    func testBackupLandsInTheDriveFolder() throws {
        try makeDrive("someone@gmail.com")
        let drive = try XCTUnwrap(CloudDriveLocator(root: root).googleDrives().first)
        let folder = try CloudDriveLocator(root: root).backupFolder(in: drive)

        var library = Library()
        library.add(Video(youtubeID: "dQw4w9WgXcQ", title: "Shared shelf", channel: "C"))
        let url = folder.appendingPathComponent(ShelfBackup.suggestedFileName())
        try BackupService().write(library, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try BackupService().read(from: url), library)
    }
}
