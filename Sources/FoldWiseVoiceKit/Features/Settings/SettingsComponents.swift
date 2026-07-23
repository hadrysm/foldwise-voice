// Shared SwiftUI building blocks for the settings panes, all consuming the
// Theme token layer (PRD #103) so every pane picks up the Editorial palette
// in both appearances.

import AppKit
import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
            .background(Theme.keycapBackground, in: RoundedRectangle(cornerRadius: Theme.keycapRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keycapRadius)
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
                        .fill(i < value ? Theme.textSecondary : Theme.hairline)
                        .frame(width: 4.5, height: 4.5)
                }
            }
        }
    }
}

func sectionHeader(_ text: String) -> some View {
    Text(text)
        .font(Theme.sectionLabel)
        .kerning(1.1)
        .foregroundStyle(Theme.textTertiary)
        .textCase(.uppercase)
        .padding(.leading, 4)
}
