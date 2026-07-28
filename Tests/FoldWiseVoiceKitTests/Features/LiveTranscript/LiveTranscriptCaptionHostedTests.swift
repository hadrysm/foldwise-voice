import AppKit
import XCTest
@testable import FoldWiseVoiceKit

/// The parts of the caption only a real panel can answer: where it lands beside
/// the Badge, how it behaves at a screen edge, and that neither surface can take
/// focus from the app being dictated into. Everything the caption *says* is
/// covered by `LiveTranscriptCaptionTests`.
@MainActor
final class LiveTranscriptCaptionHostedTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-live-caption-hosted-\(UUID().uuidString)")
    private let session = UUID()

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testCaptionStaysOffScreenUntilTheSessionHasWords() throws {
        let badge = try makeBadge()

        let opened = windowsOpened(by: {
            badge.applyLiveTranscript(.session(.started(session)))
            badge.applyLiveTranscript(.pipeline(.listening(mode: "Email")))
        })

        XCTAssertEqual(opened, [])
    }

    func testCaptionNeitherBecomesKeyNorMain() throws {
        let badge = try makeBadge()

        let caption = try showCaption(on: badge)

        XCTAssertEqual([caption.canBecomeKey, caption.canBecomeMain], [false, false])
    }

    func testCaptionIgnoresPointerInputEntirely() throws {
        let badge = try makeBadge()

        let caption = try showCaption(on: badge)

        XCTAssertTrue(caption.ignoresMouseEvents)
    }

    func testCaptionSitsCentredOnTheBadgeJustAboveIt() throws {
        let badge = try makeBadge()
        let pill = try XCTUnwrap(badgePanel())

        let caption = try showCaption(on: badge)

        XCTAssertEqual(
            [caption.frame.minY, caption.frame.midX, caption.frame.width, caption.frame.height],
            [pill.frame.maxY + 2, pill.frame.midX, 420, 82]
        )
    }

    func testCaptionClampsInsideTheScreenBesideAnEdgeBadge() throws {
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let badge = try makeBadge(anchoredAt: CGPoint(x: screen.minX + 8, y: screen.minY + 96))

        let caption = try showCaption(on: badge)

        XCTAssertEqual(caption.frame.minX, screen.minX + 4)
    }

    func testTetherKeepsPointingAtAnEdgeBadge() throws {
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let badge = try makeBadge(anchoredAt: CGPoint(x: screen.minX + 8, y: screen.minY + 96))

        let caption = try showCaption(on: badge)
        let pill = try XCTUnwrap(badgePanel())

        XCTAssertEqual(caption.frame.midX + badge.captionModel.tetherOffset, pill.frame.midX)
    }

    func testTheSessionOutcomeTakesTheCaptionOffScreen() throws {
        let badge = try makeBadge()
        let caption = try showCaption(on: badge)

        badge.applyLiveTranscript(.transcript(DictationTranscript(
            dictationSessionID: session,
            snapshot: TranscriptSnapshot(committed: "hey sam", tentative: ""),
            phase: .locked
        )))
        badge.applyLiveTranscript(.pipeline(.transcribing))
        badge.applyLiveTranscript(.pipeline(.inserted))

        XCTAssertFalse(caption.isVisible)
    }

    // MARK: - helpers

    /// A Badge that leaves the screen with the test: its panels are
    /// `.statusBar` level and borderless, so one left behind floats above every
    /// window for the life of the process.
    private func makeBadge(anchoredAt anchor: CGPoint? = nil) throws -> BadgeController {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        if let anchor {
            try config.setBadgePosition([Double(anchor.x), Double(anchor.y)])
        }
        let badge = BadgeController(config: config, onOpenApp: {})
        addTeardownBlock { @MainActor in badge.hide() }
        badge.show()
        return badge
    }

    /// Drives one streaming session as far as its first words and returns the
    /// panel that appeared for them.
    private func showCaption(on badge: BadgeController) throws -> NSPanel {
        let opened = windowsOpened(by: {
            badge.applyLiveTranscript(.session(.started(session)))
            badge.applyLiveTranscript(.pipeline(.listening(mode: "Email")))
            badge.applyLiveTranscript(.transcript(DictationTranscript(
                dictationSessionID: session,
                snapshot: TranscriptSnapshot(committed: "hey sam ", tentative: "i wanted"),
                phase: .live
            )))
        })
        return try XCTUnwrap(opened.first as? NSPanel)
    }

    private func badgePanel() -> NSPanel? {
        NSApp.windows
            .compactMap { $0 as? BadgePanel }
            .first { $0.isVisible && $0.frame.height == Theme.badgeHeight }
    }

    private func windowsOpened(by work: () -> Void) -> [NSWindow] {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        work()
        return NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }
    }
}
