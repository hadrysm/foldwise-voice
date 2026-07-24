import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModelsWorkspaceHostedTests: XCTestCase {
    func testNativeSplitProtectsBothPaneMinimumsAtCompactWidth() {
        let controller = compactSplitController()

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

    func testNativeSplitKeepsApprovedCompactGeometry() {
        let controller = compactSplitController()

        XCTAssertEqual(
            [
                controller.splitView.arrangedSubviews[0].frame.width,
                controller.splitView.dividerThickness,
                controller.splitView.arrangedSubviews[1].frame.width,
            ],
            [340, 1, 276]
        )
    }

    func testInspectedTraceRowRendersTheCanonicalLeadingIngress() throws {
        let row = try renderedColorCounts(
            ModelsTraceRowChrome(
                isInspected: true,
                isHighlighted: true,
                isKeyboardFocused: false,
                increaseContrast: false
            ),
            size: NSSize(width: 180, height: 46)
        )

        XCTAssertGreaterThan(
            row.leadingAccent,
            100,
            "the inspected row should continue the orange ingress shown in the inspector"
        )
    }

    func testTraceRowRendersFocusOnlyWhenItsCallSiteRequestsIt() throws {
        let resting = try renderedColorCounts(
            ModelsTraceRowChrome(
                isInspected: false,
                isHighlighted: false,
                isKeyboardFocused: false,
                increaseContrast: false
            ),
            size: NSSize(width: 180, height: 46)
        )
        let focused = try renderedColorCounts(
            ModelsTraceRowChrome(
                isInspected: false,
                isHighlighted: false,
                isKeyboardFocused: true,
                increaseContrast: false
            ),
            size: NSSize(width: 180, height: 46)
        )

        XCTAssertLessThan(resting.accent, 20)
        XCTAssertGreaterThan(focused.accent, resting.accent + 300)
    }

    func testTraceInspectorHeaderRendersTheCanonicalIngress() throws {
        let inspector = try renderedColorCounts(
            ModelsTraceInspectorHeader(isInspected: true) {
                Color.clear.frame(height: 70)
            },
            size: NSSize(width: 180, height: 70)
        )

        XCTAssertGreaterThan(inspector.accent, 160)
    }

    func testTraceRowStrengthensItsBoundaryForIncreaseContrast() throws {
        let standard = try renderedColorCounts(
            ModelsTraceRowChrome(
                isInspected: false,
                isHighlighted: false,
                isKeyboardFocused: false,
                increaseContrast: false
            ),
            size: NSSize(width: 180, height: 46)
        )
        let increased = try renderedColorCounts(
            ModelsTraceRowChrome(
                isInspected: false,
                isHighlighted: false,
                isKeyboardFocused: false,
                increaseContrast: true
            ),
            size: NSSize(width: 180, height: 46)
        )

        XCTAssertGreaterThan(increased.strongBoundary, standard.strongBoundary + 300)
    }

    func testInspectionAccessibilityValueKeepsInspectionDistinctFromSavedSelection() {
        XCTAssertEqual(
            ModelsRowAccessibility.value(
                isInspected: true,
                progressValue: "43 percent"
            ),
            "Inspected, 43 percent"
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
                rootView: ModelsTraceRowChrome(
                    isInspected: false,
                    isHighlighted: isHighlighted,
                    isKeyboardFocused: false,
                    increaseContrast: false
                )
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

        XCTAssertGreaterThan(
            colorDistance(resting, highlighted),
            0.05,
            "hovering a model row should visibly change its background"
        )
    }

    private struct RenderedColorCounts {
        let accent: Int
        let leadingAccent: Int
        let strongBoundary: Int
    }

    private func compactSplitController() -> NSSplitViewController {
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
        return controller
    }

    private func renderedColorCounts(
        _ view: some View,
        size: NSSize
    ) throws -> RenderedColorCounts {
        let controller = NSHostingController(
            rootView: view
                .environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height)
        )
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        let accentColor = try renderedTokenColor(Theme.accent)
        let strongBoundaryColor = try renderedTokenColor(Theme.borderStrong)
        var accentCount = 0
        var leadingAccentCount = 0
        var strongBoundaryCount = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                if colorDistance(pixel, accentColor) < 0.08 {
                    accentCount += 1
                    if x < 4 {
                        leadingAccentCount += 1
                    }
                }
                if colorDistance(pixel, strongBoundaryColor) < 0.08 {
                    strongBoundaryCount += 1
                }
            }
        }
        return RenderedColorCounts(
            accent: accentCount,
            leadingAccent: leadingAccentCount,
            strongBoundary: strongBoundaryCount
        )
    }

    private func renderedTokenColor(_ color: Color) throws -> NSColor {
        let controller = NSHostingController(
            rootView: color
                .environment(\.colorScheme, .light)
                .frame(width: 2, height: 2)
        )
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.frame = NSRect(x: 0, y: 0, width: 2, height: 2)
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

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }
}
