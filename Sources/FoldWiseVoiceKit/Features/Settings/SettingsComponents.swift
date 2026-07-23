import AppKit
import SwiftUI

struct SignalLedgerSection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmberSectionLabel(title, symbolName: symbolName)
                .padding(.leading, 4)
            EmberSurface {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignalLedgerRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct SignalLedgerDivider: View {
    var body: some View {
        EmberHairline(axis: .horizontal)
            .padding(.leading, 12)
    }
}

struct SignalLedgerFeedback: View {
    let kind: EmberStatusKind
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        EmberStatusNotice(
            kind: kind,
            title: title,
            detail: detail,
            ingressWidth: Theme.selectionIngressWidth,
            actionTitle: actionTitle,
            action: action
        )
        .padding(.trailing, 10)
        .frame(minHeight: 44)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

struct Keycap: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Text(text)
            .font(Theme.mono(11.5, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        Theme.essentialBorderColor(increaseContrast: usesStrongBoundary),
                        lineWidth: Theme.essentialBorderWidth(
                            increaseContrast: usesStrongBoundary
                        )
                    )
            )
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }
}

struct RatingDots: View {
    let label: String
    let value: Int // of 5
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 2.5) {
                ForEach(0 ..< 5, id: \.self) { i in
                    Circle()
                        .fill(i < value ? Theme.textSecondary : Theme.border)
                        .frame(width: 4.5, height: 4.5)
                }
            }
        }
    }
}
