import SwiftUI

struct ModelsRatingMeter: View {
    let rating: ModelsRating
    let isHighlighted: Bool

    var body: some View {
        Group {
            switch rating {
            case let .rated(value):
                let activeColor = isHighlighted ? Theme.accent : Theme.textSecondary
                HStack(spacing: 2) {
                    ForEach(1 ... 5, id: \.self) { segment in
                        Capsule()
                            .fill(segment <= value ? activeColor : Theme.border)
                            .frame(width: 5, height: 10)
                    }
                }
            case .notRated:
                Text("—")
                    .font(Theme.ui(9.5, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating.accessibilityText)
        .help(rating.accessibilityText)
    }
}
