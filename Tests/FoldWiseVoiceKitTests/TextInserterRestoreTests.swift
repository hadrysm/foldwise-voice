// The clipboard-restore state machine in TextInserter.insert: the previous
// clipboard comes back after the paste window, unless the user (or a newer
// dictation) wrote to the pasteboard first. Uses a private named pasteboard —
// the real NSPasteboard API against an isolated instance, no fakes — with the
// paste keystroke and Accessibility check injected at the boundary.

import AppKit
import XCTest
@testable import FoldWiseVoiceKit

final class TextInserterRestoreTests: XCTestCase {
    /// XCTest builds a fresh instance per test method, so every test gets its
    /// own uniquely named pasteboard.
    private let pasteboard = NSPasteboard(name: .init("foldwise-tests-\(UUID().uuidString)"))

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    @MainActor
    private func insert(_ text: String, trusted: Bool = true) -> Bool {
        TextInserter.insert(
            text, pasteboard: pasteboard,
            trusted: { trusted }, postPaste: {},
            restoreDelay: 0.05
        )
    }

    /// Spin the run loop until well past the 0.05s restore delay.
    private func waitForRestoreWindow() {
        let window = expectation(description: "past restore window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.fulfill() }
        wait(for: [window], timeout: 2)
    }

    @MainActor
    func testRestoresPreviousClipboardAfterPasteWindow() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertTrue(insert("dictated"))
        waitForRestoreWindow()
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testUserCopyDuringPasteWindowIsNotClobbered() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertTrue(insert("dictated"))
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)
        waitForRestoreWindow()
        XCTAssertEqual(pasteboard.string(forType: .string), "user copy")
    }

    @MainActor
    func testNewerInsertSupersedesPendingRestore() {
        // The first insert's restore of "previous" is canceled; the second
        // insert restores what it found on the pasteboard: "first".
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertTrue(insert("first"))
        XCTAssertTrue(insert("second"))
        waitForRestoreWindow()
        XCTAssertEqual(pasteboard.string(forType: .string), "first")
    }

    @MainActor
    func testWithoutAccessibilityLeavesTranscriptOnClipboardForGood() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertFalse(insert("dictated", trusted: false))
        waitForRestoreWindow()
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
    }

    @MainActor
    func testEmptyTextIsRejectedAndPasteboardUntouched() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertFalse(insert(""))
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testEmptyPasteboardMeansNothingToRestore() {
        pasteboard.clearContents()
        XCTAssertTrue(insert("dictated"))
        waitForRestoreWindow()
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
    }
}
