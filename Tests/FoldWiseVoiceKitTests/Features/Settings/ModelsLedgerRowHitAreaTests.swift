import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

/// The ledger's cards look like one tap target each, so every point a card
/// paints has to select it — including the padding band the chrome draws around
/// the row's text. These tests click the hosted pane for real and read the
/// resulting inspection back through the injected projector.
@MainActor
final class ModelsLedgerRowHitAreaTests: XCTestCase {
    /// Row centres for the fixture below, at the hosted geometry these tests
    /// pin. Both sit on the row's text, which has always been clickable.
    private let firstRowCentre: CGFloat = 232
    private let secondRowCentre: CGFloat = 283
    /// Inside every card's leading padding, outside its text.
    private let cardLeadingEdge: CGFloat = 20

    func testCardPaddingBetweenTwoRowsLeavesOnlyTheCanvasGapDead() {
        let ledger = HostedLedger()
        defer { ledger.tearDown() }

        XCTAssertEqual(
            [
                ledger.selection(clickingAt: CGPoint(x: 60, y: firstRowCentre)),
                ledger.selection(clickingAt: CGPoint(x: 60, y: secondRowCentre)),
            ],
            [.speechRecognition("parakeet-v2"), .speechRecognition("parakeet-eou-320")],
            "the fixture's row centres moved — the probes below no longer straddle two cards"
        )

        var deadRun = 0
        var longestDeadRun = 0
        for y in stride(from: firstRowCentre, through: secondRowCentre, by: 1) {
            if ledger.selectionChanges(clickingAt: CGPoint(x: 60, y: y)) {
                deadRun = 0
            } else {
                deadRun += 1
                longestDeadRun = max(longestDeadRun, deadRun)
            }
        }

        XCTAssertLessThanOrEqual(
            CGFloat(longestDeadRun),
            ModelsLedgerRowMetrics.interRowSpacing,
            "only the canvas gap between two cards may ignore a click; a longer dead "
                + "run means a card's own padding stopped answering"
        )
    }

    func testClickingACardsLeadingPaddingSelectsTheRow() {
        let ledger = HostedLedger()
        defer { ledger.tearDown() }

        XCTAssertEqual(
            ledger.selection(clickingAt: CGPoint(x: cardLeadingEdge, y: firstRowCentre)),
            .speechRecognition("parakeet-v2")
        )
    }

    /// Hosts the pane in a window tall enough that the ledger never scrolls —
    /// inspecting a row scrolls it to centre, which would move every later
    /// probe off the card it was aimed at.
    @MainActor
    private final class HostedLedger {
        private let hosting: NSHostingView<ModelsCombinedPane>
        private let window: NSWindow
        private let observed = Observed()

        final class Observed {
            var inspectedID: ModelsRowID?
        }

        init() {
            let model = SettingsModel()
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
            model.installed = []
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
            hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 1400)
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
        }

        func tearDown() {
            window.orderOut(nil)
        }

        /// Clicks `point` and reports the row it inspected.
        func selection(clickingAt point: CGPoint) -> ModelsRowID? {
            click(at: point)
            return observed.inspectedID
        }

        /// Parks the inspection on a row the probe cannot reach, then reports
        /// whether `point` moved it. Without the reset a click that lands on
        /// dead padding is indistinguishable from one that re-selects the row
        /// already inspected.
        func selectionChanges(clickingAt point: CGPoint) -> Bool {
            click(at: CGPoint(x: 60, y: 167))
            let parked = observed.inspectedID
            click(at: point)
            return observed.inspectedID != parked
        }

        private func click(at point: CGPoint) {
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
                    return
                }
                NSApp.sendEvent(event)
            }
            hosting.layoutSubtreeIfNeeded()
        }
    }
}
