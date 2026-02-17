import SwiftUI

/// Animated refresh button
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onChange(of: isRefreshing) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    rotation = 0
                }
            }
        }
        .help("Refresh usage data")
    }
}
