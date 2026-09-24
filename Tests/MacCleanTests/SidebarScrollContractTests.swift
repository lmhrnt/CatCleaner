import Foundation
import XCTest

/// Guards the macOS sidebar scrolling contract.
///
/// SwiftUI List + custom collapsible rows previously let the sidebar scroll
/// downward but could leave it unable to scroll back upward. The module list
/// must remain a plain vertical ScrollView, while Settings stays pinned below it.
final class SidebarScrollContractTests: XCTestCase {
    private var sidebarSource: String {
        get throws {
            let root = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return try String(
                contentsOf: root.appending(path: "Sources/MacClean/Views/Sidebar/SidebarView.swift"),
                encoding: .utf8
            )
        }
    }

    func testSidebarUsesBidirectionalVerticalScrollViewInsteadOfListSelection() throws {
        let source = try sidebarSource

        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("ScrollView(.vertical)"))
        XCTAssertTrue(source.contains(".scrollIndicators(.automatic)"))
        XCTAssertTrue(source.contains("proxy.scrollTo(newValue, anchor: .center)"))
        XCTAssertFalse(source.contains("List(selection:"))
    }

    func testSettingsFooterRemainsOutsideScrollableModuleList() throws {
        let source = try sidebarSource
        let scroll = try XCTUnwrap(source.range(of: "ScrollViewReader"))
        let divider = try XCTUnwrap(source.range(of: "Divider().opacity(0.4)"))
        let footer = try XCTUnwrap(source.range(of: "settingsFooter", range: divider.upperBound..<source.endIndex))

        XCTAssertLessThan(scroll.lowerBound, divider.lowerBound)
        XCTAssertLessThan(divider.lowerBound, footer.lowerBound)
    }
}
