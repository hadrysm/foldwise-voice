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
    private let scheduler = ManualRestoreScheduler()

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    @MainActor
    private func insert(_ text: String, trusted: Bool = true) -> Bool {
        insert(text, trusted: trusted, postPaste: {})
    }

    @MainActor
    private func insert(
        _ text: String,
        trusted: Bool = true,
        postPaste: @escaping () -> Void
    ) -> Bool {
        TextInserter.insert(
            text, pasteboard: pasteboard,
            trusted: { trusted }, postPaste: postPaste,
            restoreDelay: 0.4,
            scheduleRestore: scheduler.schedule
        )
    }

    @MainActor
    func testRestoresPreviousClipboardAfterPasteWindow() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        _ = insert("dictated")
        scheduler.scheduled.last?()
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testUserCopyDuringPasteWindowIsNotClobbered() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        _ = insert("dictated")
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)
        scheduler.scheduled.last?()
        XCTAssertEqual(pasteboard.string(forType: .string), "user copy")
    }

    @MainActor
    func testNewerInsertSupersedesPendingRestore() {
        // Even if the first insert's canceled work is delivered late, the
        // second insert restores what it found on the pasteboard: "first".
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        _ = insert("first")
        _ = insert("second")
        scheduler.scheduled.forEach { $0() }
        XCTAssertEqual(pasteboard.string(forType: .string), "first")
    }

    @MainActor
    func testNewerInsertCancelsPendingRestore() {
        pasteboard.setString("previous", forType: .string)
        _ = insert("first")
        _ = insert("second")
        XCTAssertTrue(scheduler.cancelled)
    }

    @MainActor
    func testWithoutAccessibilityReturnsClipboardFallback() {
        XCTAssertFalse(insert("dictated", trusted: false))
    }

    @MainActor
    func testWithoutAccessibilityLeavesTranscriptOnClipboardForGood() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        _ = insert("dictated", trusted: false)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
    }

    @MainActor
    func testEmptyTextIsRejected() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        XCTAssertFalse(insert(""))
    }

    @MainActor
    func testEmptyTextLeavesPasteboardUntouched() {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        _ = insert("")
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testEmptyPasteboardMeansNothingToRestore() {
        pasteboard.clearContents()
        _ = insert("dictated")
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
    }

    @MainActor
    func testSuccessfulInsertionReturnsTrue() {
        XCTAssertTrue(insert("dictated"))
    }

    @MainActor
    func testSuccessfulInsertionPostsPaste() {
        var posted = false
        _ = insert("dictated", postPaste: { posted = true })
        XCTAssertTrue(posted)
    }
}

private final class ManualRestoreScheduler {
    private(set) var scheduled: [() -> Void] = []
    private(set) var cancelled = false

    func schedule(_: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        scheduled.append(action)
        return { self.cancelled = true }
    }
}
