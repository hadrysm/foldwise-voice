import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModelsWorkspaceHostedTests: XCTestCase {
    func testNativeSplitProtectsBothPaneMinimumsAtCompactWidth() {
        let controller = ModelsNativeSplitController.make(
            leading: Color.clear,
            trailing: Color.clear
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 617, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(
            ModelsSplitGeometry.initialLedgerWidth(
                totalWidth: controller.splitView.bounds.width,
                dividerWidth: controller.splitView.dividerThickness
            ),
            ofDividerAt: 0
        )
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            [
                controller.splitView.arrangedSubviews[0].frame.width
                    >= ModelsSplitGeometry.ledgerMinimum,
                controller.splitView.arrangedSubviews[1].frame.width
                    >= ModelsSplitGeometry.inspectorMinimum,
            ],
            [true, true]
        )
    }
}
