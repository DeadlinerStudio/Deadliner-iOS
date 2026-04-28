import SwiftUI
import WidgetKit

struct MediumHomeWidgetView: View {
    let entry: DeadlinerEntry

    private let gridRows = Array(repeating: GridItem(.flexible(minimum: 8), spacing: 3), count: 7)
    private let gridSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            GeometryReader { proxy in
                let maxCellByHeight = (proxy.size.height - gridSpacing * 6) / 7
                let columnCount = max(1, Int(ceil(Double(entry.contributionStats.count) / 7.0)))
                let maxCellByWidth = (proxy.size.width - CGFloat(columnCount - 1) * gridSpacing) / CGFloat(columnCount)
                let cellSize = max(5, min(maxCellByHeight, maxCellByWidth))

                LazyHGrid(rows: gridRows, spacing: gridSpacing) {
                    ForEach(entry.contributionStats) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(for: day.count))
                            .frame(width: cellSize, height: cellSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }

            legend
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            Color("WidgetBackground")
        }
    }

    private var header: some View {
        HStack {
            Text("活跃热力图")
                .font(.system(size: 14, weight: .bold))

            Spacer(minLength: 8)

            Text("\(entry.contributionStats.count)天内")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(heatColor(for: level))
                    .frame(width: 8, height: 8)
            }

            Text("多")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func heatColor(for count: Int) -> Color {
        if count == 0 { return Color(UIColor.systemGray6) }
        if count < 2 { return Color.green.opacity(0.3) }
        if count < 4 { return Color.green.opacity(0.5) }
        if count < 6 { return Color.green.opacity(0.7) }
        return Color.green
    }
}
