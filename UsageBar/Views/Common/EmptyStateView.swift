import SwiftUI

/// Empty state shown when no providers are configured
struct EmptyStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No Providers Configured")
                    .font(.headline)

                Text("Add an API key to start tracking your AI usage across providers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
