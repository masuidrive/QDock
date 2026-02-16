import SwiftUI
import Charts

/// Mini trend chart showing daily usage over time
@available(macOS 14.0, *)
struct TrendChartView: View {
    let dailyData: [DailyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Usage Trend")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dailyData.isEmpty {
                Text("Not enough data for trend")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(dailyData) { day in
                    // Input tokens area
                    AreaMark(
                        x: .value("Date", day.date),
                        y: .value("Input", day.inputTokens)
                    )
                    .foregroundStyle(.blue.opacity(0.15))

                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Input", day.inputTokens)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    // Output tokens line
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Output", day.outputTokens)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(formatTokens(intValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .trailing) {
                    HStack(spacing: 12) {
                        legendItem("Input", color: .blue)
                        legendItem("Output", color: .green)
                    }
                    .font(.caption2)
                }
                .frame(height: 120)
            }
        }
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.0fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
