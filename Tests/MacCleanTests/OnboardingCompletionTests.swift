import Foundation
import XCTest

@testable import MacClean

/// Source-contract tests for first-run onboarding.
///
/// The app must not mark onboarding complete merely because the sheet was
/// presented. Closing the sheet early should cause it to appear again on a
/// later launch; only the final Get Started action completes it.
final class OnboardingCompletionTests: XCTestCase {
    func testAppMarksCompletionOnlyFromOnCompleteCallback() throws {
        let source = try source("Sources/MacClean/App/MacCleanApp.swift")

        XCTAssertTrue(
            source.contains("onComplete: { hasCompletedOnboarding = true }"),
            "The final onboarding action must own the completion write"
        )
        XCTAssertFalse(
            source.contains("showOnboarding = true\n                        hasCompletedOnboarding = true"),
            "Presenting onboarding must not silently mark it complete"
        )
    }

    func testDismissButtonDoesNotCallCompletion() throws {
        let source = try source("Sources/MacClean/Views/Shared/OnboardingView.swift")

        XCTAssertTrue(source.contains("Button { isPresented = false }"))
        XCTAssertTrue(
            source.contains("onComplete()\n                        isPresented = false"),
            "Only the final Get Started button should call onComplete"
        )
    }

    func testSettingsCanReopenOnboardingImmediately() throws {
        let appState = try source("Sources/MacClean/App/AppState.swift")
        let settings = try source("Sources/MacClean/Views/Settings/SettingsPageView.swift")
        let app = try source("Sources/MacClean/App/MacCleanApp.swift")

        XCTAssertTrue(appState.contains("func requestOnboarding()"))
        XCTAssertTrue(settings.contains("appState.requestOnboarding()"))
        XCTAssertTrue(app.contains(".onChange(of: appState.onboardingRequestNonce)"))
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
