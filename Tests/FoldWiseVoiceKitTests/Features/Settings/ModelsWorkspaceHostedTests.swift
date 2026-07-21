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

    func testCancelableASRRowKeepsIdentityVisibleAtCompactWidth() throws {
        let model = SettingsModel()
        model.applyASRLifecycleSnapshot(ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(
                    entry: $0,
                    isAvailable: ["parakeet-v3", "whisper-large-v3-turbo"].contains($0.id)
                )
            },
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            recovery: nil,
            operation: .downloading(modelID: "whisper-small", fraction: 0.43),
            failure: nil,
            isDictationBlocked: false
        ))
        model.installed = [
            OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1_900_000_000),
        ]
        let controller = NSHostingController(
            rootView: ModelsCombinedPane(model: model)
                .frame(width: 617, height: 780)
                .environment(\.colorScheme, .light)
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 617, height: 780)
        controller.view.layoutSubtreeIfNeeded()
        let splitLayoutCompleted = expectation(description: "native split layout completed")
        DispatchQueue.main.async { splitLayoutCompleted.fulfill() }
        wait(for: [splitLayoutCompleted], timeout: 1)
        controller.view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / controller.view.bounds.width
        var contrastingPixels = 0
        for y in stride(from: 326.0, through: 356.0, by: 1 / scale) {
            for x in stride(from: 28.0, through: 38.0, by: 1 / scale) {
                guard let color = bitmap.colorAt(
                    x: Int(x * scale), y: Int(y * scale)
                )?.usingColorSpace(.sRGB) else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.65 {
                    contrastingPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(
            contrastingPixels,
            20,
            "the inline Cancel control consumed the ASR row's identity cell"
        )
    }
}
