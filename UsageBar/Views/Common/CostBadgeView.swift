import SwiftUI

/// Displays a cost value as a styled badge
struct CostBadgeView: View {
    let cost: Decimal
    let size: BadgeSize

    enum BadgeSize {
        case small, medium, large
    }

    init(cost: Decimal, size: BadgeSize = .medium) {
        self.cost = cost
        self.size = size
    }

    var body: some View {
        Text(formattedCost)
            .font(font)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(costColor)
    }

    private var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: cost as NSDecimalNumber) ?? "$0.00"
    }

    private var font: Font {
        switch size {
        case .small: return .caption
        case .medium: return .body
        case .large: return .title2
        }
    }

    private var costColor: Color {
        if cost > 50 { return .red }
        if cost > 20 { return .orange }
        if cost > 5 { return .primary }
        return .primary
    }
}
