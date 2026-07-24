import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class EmberChromeTests: XCTestCase {
    private struct ToastRenderAnalysis {
        let strongBoundaryPixels: Int
        let bleedPixels: Int
    }

    func testGlobalToastMotionRisesFromBelowAndExitsTowardTheBottom() {
        XCTAssertEqual(GlobalStatusToastMotion.insertionOffset, 20)
        XCTAssertEqual(GlobalStatusToastMotion.removalOffset, 12)
        XCTAssertLessThan(GlobalStatusToastMotion.insertionScale, 1)
        XCTAssertLessThan(GlobalStatusToastMotion.removalScale, 1)
    }

    @MainActor
    func testGlobalToastUsesStrongContrastBoundary() throws {
        XCTAssertGreaterThan(
            try analyzeGlobalToast(increaseContrast: true).strongBoundaryPixels,
            100
        )
    }

    @MainActor
    func testGlobalToastCastsNoShadowBleed() throws {
        XCTAssertEqual(
            try analyzeGlobalToast(increaseContrast: false).bleedPixels,
            0
        )
    }

    func testSemanticNoticeUsesCanonicalIngressByDefault() {
        let notice = EmberStatusNotice(kind: .success, title: "Saved")

        XCTAssertEqual(notice.ingressWidth, Theme.noticeIngressWidth)
    }

    func testSemanticNoticesPairColorWithPermanentIconAndTextCues() {
        XCTAssertEqual(
            EmberStatusKind.allCases.map {
                [$0.accessibilityName, $0.symbolName, $0.colorRole.rawValue]
            },
            [
                ["Success", "checkmark.circle.fill", "success"],
                ["Warning", "exclamationmark.triangle.fill", "warning"],
                ["Error", "xmark.octagon.fill", "error"],
            ]
        )
    }

    @MainActor
    private func analyzeGlobalToast(
        increaseContrast: Bool
    ) throws -> ToastRenderAnalysis {
        let toast = GlobalStatusToast(
            title: "Saved",
            isError: false,
            increaseContrastOverride: increaseContrast
        )
        .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: toast)
        let toastSize = hosting.fittingSize
        let margin: CGFloat = 24
        let canvas = ZStack {
            Color.white
            toast
        }
        .frame(
            width: toastSize.width + margin * 2,
            height: toastSize.height + margin * 2
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let strongBoundary = try renderedColor(Theme.borderStrong)

        var strongBoundaryPixels = 0
        var bleedPixels = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(NSColorSpace.sRGB)
                else { continue }
                if colorDistance(pixel, strongBoundary) < 0.08 {
                    strongBoundaryPixels += 1
                }
                let outsideToast = x < Int(margin - 1)
                    || x >= bitmap.pixelsWide - Int(margin - 1)
                    || y < Int(margin - 1)
                    || y >= bitmap.pixelsHigh - Int(margin - 1)
                if outsideToast,
                   min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.98 {
                    bleedPixels += 1
                }
            }
        }

        return ToastRenderAnalysis(
            strongBoundaryPixels: strongBoundaryPixels,
            bleedPixels: bleedPixels
        )
    }

    @MainActor
    private func renderedColor(_ color: Color) throws -> NSColor {
        let renderer = ImageRenderer(
            content: color
                .environment(\.colorScheme, .light)
                .frame(width: 2, height: 2)
        )
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        return try XCTUnwrap(
            bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.sRGB)
        )
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }
}
