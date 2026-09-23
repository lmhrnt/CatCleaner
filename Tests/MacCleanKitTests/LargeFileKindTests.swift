import Foundation
import XCTest

@testable import MacCleanKit

final class LargeFileKindTests: XCTestCase {
    func testIOSBackupPathWinsOverExtension() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Library/Application Support/MobileSync/Backup/device123/file.dmg"),
            name: "file.dmg",
            size: 100,
            allocatedSize: 100,
            isDirectory: false
        )

        XCTAssertEqual(LargeFileKind.classify(item), .iosBackups)
    }

    func testVirtualMachinePackagesAndDisksAreRecognized() {
        let pvm = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/Parallels/Windows 11.pvm"),
            name: "Windows 11.pvm",
            size: 100,
            allocatedSize: 100,
            isDirectory: true,
            isPackage: true
        )
        let disk = FileItem(
            url: URL(fileURLWithPath: "/Users/test/VM/Linux.qcow2"),
            name: "Linux.qcow2",
            size: 100,
            allocatedSize: 100,
            isDirectory: false
        )

        XCTAssertEqual(LargeFileKind.classify(pvm), .virtualMachines)
        XCTAssertEqual(LargeFileKind.classify(disk), .virtualMachines)
    }

    func testOrdinaryDiskImageIsNotVirtualMachine() {
        let dmg = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Downloads/Installer.dmg"),
            name: "Installer.dmg",
            size: 100,
            allocatedSize: 100,
            isDirectory: false
        )

        XCTAssertEqual(LargeFileKind.classify(dmg), .diskImages)
    }

    func testFilesInsideVMContainerStayInVirtualMachineBucket() {
        let nested = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/Parallels/Windows.pvm/Disk0.hds"),
            name: "Disk0.hds",
            size: 100,
            allocatedSize: 100,
            isDirectory: false
        )

        XCTAssertEqual(LargeFileKind.classify(nested), .virtualMachines)
    }

    func testCommonMediaAndDocumentTypes() {
        XCTAssertEqual(kind("movie.mov"), .video)
        XCTAssertEqual(kind("track.flac"), .audio)
        XCTAssertEqual(kind("photo.heic"), .images)
        XCTAssertEqual(kind("report.pdf"), .documents)
        XCTAssertEqual(kind("archive.7z"), .archives)
        XCTAssertEqual(kind("installer.pkg"), .installers)
    }

    func testGroupingDeduplicatesByURLAndSortsLargestFirst() {
        let aSmall = item("/tmp/a.mov", size: 100)
        let aLarge = item("/tmp/a.mov", size: 300)
        let b = item("/tmp/b.mov", size: 200)
        let c = item("/tmp/c.pdf", size: 400)

        let groups = LargeFileKind.grouped([aSmall, b, c, aLarge])

        let video = groups.first(where: { $0.kind == .video })
        XCTAssertEqual(video?.items.map(\.size), [300, 200])

        let documents = groups.first(where: { $0.kind == .documents })
        XCTAssertEqual(documents?.items.map(\.size), [400])
    }

    private func kind(_ name: String) -> LargeFileKind {
        LargeFileKind.classify(
            item("/tmp/\(name)", size: 1)
        )
    }

    private func item(_ path: String, size: UInt64) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            size: size,
            allocatedSize: size,
            isDirectory: false
        )
    }
}
