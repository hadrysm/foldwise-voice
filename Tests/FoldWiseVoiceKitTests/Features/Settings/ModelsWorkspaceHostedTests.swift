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

    func testInspectorPrimaryActionSitsUnderTheInspectedModelContent() throws {
        let model = SettingsModel()
        model.applyASRLifecycleSnapshot(ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(entry: $0, isAvailable: $0.id == "parakeet-v3")
            },
            storedSelection: "parakeet-v2",
            effectiveSelection: "parakeet-v3",
            recovery: .storedSelectionUnavailable(
                modelID: "parakeet-v2",
                fallbackModelID: "parakeet-v3"
            ),
            operation: nil,
            failure: nil,
            isDictationBlocked: false
        ))
        let controller = NSHostingController(
            rootView: ModelsCombinedPane(model: model)
                .frame(width: 900, height: 700)
                .environment(\.colorScheme, .light)
                .tint(Theme.accent)
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
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
        let inspectorStartX = controller.view.bounds.width * 0.56

        func accentPixelCount(yRange: ClosedRange<CGFloat>) -> Int {
            var count = 0
            for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: 1 / scale) {
                for x in stride(
                    from: inspectorStartX,
                    through: controller.view.bounds.width - 20,
                    by: 1 / scale
                ) {
                    guard let color = bitmap.colorAt(
                        x: Int(x * scale), y: Int(y * scale)
                    )?.usingColorSpace(.sRGB) else { continue }
                    if color.redComponent > 0.65,
                       color.greenComponent > 0.12,
                       color.greenComponent < 0.5,
                       color.blueComponent < 0.3 {
                        count += 1
                    }
                }
            }
            return count
        }

        XCTAssertGreaterThan(
            accentPixelCount(yRange: 300 ... 440),
            100,
            "the primary action should appear directly beneath the model content"
        )
        XCTAssertLessThan(
            accentPixelCount(yRange: 100 ... 190),
            20,
            "the primary action should not be pinned to the inspector bottom"
        )
    }

    func testHighlightedLedgerRowChangesItsBackground() throws {
        func renderedCenterColor(isHighlighted: Bool) throws -> NSColor {
            let controller = NSHostingController(
                rootView: ZStack {
                    Theme.windowBackground
                    Theme.sidebarBackground.opacity(0.46)
                    ModelsLedgerRowBackground(isHighlighted: isHighlighted)
                }
                .frame(width: 80, height: 40)
            )
            controller.view.appearance = NSAppearance(named: .darkAqua)
            controller.view.frame = NSRect(x: 0, y: 0, width: 80, height: 40)
            controller.view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(
                controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
            )
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            return try XCTUnwrap(
                bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                    .usingColorSpace(.sRGB)
            )
        }

        let resting = try renderedCenterColor(isHighlighted: false)
        let highlighted = try renderedCenterColor(isHighlighted: true)
        let colorDistance = abs(resting.redComponent - highlighted.redComponent)
            + abs(resting.greenComponent - highlighted.greenComponent)
            + abs(resting.blueComponent - highlighted.blueComponent)

        XCTAssertGreaterThan(
            colorDistance,
            0.05,
            "hovering a model row should visibly change its background"
        )
    }
}
