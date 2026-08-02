import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

/// The ledger scrolls the inspected row to centre so a keyboard or deep-linked
/// inspection is never left off-screen. A click is the one arrival that must
/// not scroll: the row is already under the pointer, and centring one that sits
/// past the halfway mark clamps to the bottom of the list.
@MainActor
final class ModelsLedgerScrollTests: XCTestCase {
    func testClickingARowLeavesTheLedgerWhereTheUserScrolledIt() throws {
        let ledger = try HostedScrollingLedger()
        defer { ledger.tearDown() }
        ledger.scroll(to: 200)

        let picked = ledger.click(at: CGPoint(x: 60, y: 560))

        XCTAssertNotNil(picked, "the probe missed every card — the fixture's geometry moved")
        XCTAssertEqual(
            ledger.offset,
            200,
            accuracy: 1,
            "clicking a visible card scrolled the ledger out from under the pointer"
        )
    }

    /// The failure this guards is specifically a jump to the end of the list:
    /// centring a row in the ledger's lower half clamps to the maximum offset.
    func testClickingALowerHalfRowDoesNotFlingTheLedgerToTheBottom() throws {
        let ledger = try HostedScrollingLedger()
        defer { ledger.tearDown() }
        ledger.scroll(to: 200)

        ledger.click(at: CGPoint(x: 60, y: 640))

        XCTAssertLessThan(ledger.offset, ledger.maximumOffset - 1)
    }

    /// The other half of the rule: an inspection the app moves for the user —
    /// here a Mode deep-linking into its Polish model — still has to scroll.
    func testDeepLinkedInspectionScrollsTheRowIntoView() throws {
        let ledger = try HostedScrollingLedger()
        defer { ledger.tearDown() }
        ledger.click(at: CGPoint(x: 60, y: 200))
        XCTAssertEqual(ledger.offset, 0, accuracy: 1, "the fixture should start at the top")

        ledger.requestPolishInspection(of: ModelCatalog.entries[ModelCatalog.entries.count - 1].name)

        XCTAssertGreaterThan(
            ledger.offset,
            1,
            "a deep link to a row below the fold left the ledger parked at the top"
        )
    }

    /// Hosts the pane short enough that the ledger genuinely overflows, with
    /// every catalogue model installed so the Polish section fills out.
    @MainActor
    private final class HostedScrollingLedger {
        private let model: SettingsModel
        private let hosting: NSHostingView<ModelsCombinedPane>
        private let window: NSWindow
        private let observed = Observed()
        private let scrollView: NSScrollView

        final class Observed {
            var inspectedID: ModelsRowID?
        }

        init() throws {
            model = SettingsModel()
            model.applyASRLifecycleSnapshot(ASRModelLifecycleSnapshot(
                models: ASRModelCatalog.entries.map {
                    ASRModelDescriptor(entry: $0, isAvailable: $0.id == "parakeet-v3")
                },
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                recovery: nil,
                operation: nil,
                failure: nil,
                isDictationBlocked: false
            ))
            model.installed = ModelCatalog.entries.map {
                OllamaClient.InstalledModel(name: $0.name, sizeBytes: 1_500_000_000)
            }
            let observed = observed
            hosting = NSHostingView(rootView: ModelsCombinedPane(
                interface: model.modelsPaneInterface,
                project: { input in
                    observed.inspectedID = input.inspectedID
                    return ModelsWorkspaceProjection.make(
                        asrSnapshot: input.asrSnapshot,
                        asrFailures: input.asrFailures,
                        polishState: input.polishState,
                        modes: input.modes,
                        inspectedID: input.inspectedID,
                        previousPolishRowIDs: input.previousPolishRowIDs
                    )
                }
            ))
            hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            NSApp.finishLaunching()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            hosting.layoutSubtreeIfNeeded()
            Self.settle(hosting)

            // The ledger is the leading pane of the split, so it is the
            // left-most of the two scrollers the pane hosts.
            let candidate = Self.scrollViews(in: hosting)
                .min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            scrollView = try XCTUnwrap(candidate, "the Models ledger hosts no scroll view")
            try XCTSkipUnless(
                maximumOffset > 0,
                "the fixture no longer overflows the hosted window, so nothing can scroll"
            )
        }

        func tearDown() {
            window.orderOut(nil)
        }

        var offset: CGFloat {
            scrollView.contentView.bounds.origin.y
        }

        var maximumOffset: CGFloat {
            (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height
        }

        func scroll(to offset: CGFloat) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            Self.settle(hosting)
        }

        func requestPolishInspection(of name: String) {
            model.requestedPolishInspection = name
            Self.settle(hosting)
        }

        @discardableResult
        func click(at point: CGPoint) -> ModelsRowID? {
            let windowPoint = hosting.convert(NSPoint(x: point.x, y: point.y), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type,
                    location: windowPoint,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                ) else {
                    XCTFail("Couldn't create a mouse event for the Models ledger.")
                    return nil
                }
                NSApp.sendEvent(event)
            }
            Self.settle(hosting)
            return observed.inspectedID
        }

        private static func settle(_ hosting: NSView) {
            for _ in 0 ..< 8 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                hosting.layoutSubtreeIfNeeded()
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            let here = (view as? NSScrollView).map { [$0] } ?? []
            return here + view.subviews.flatMap(scrollViews(in:))
        }
    }
}
