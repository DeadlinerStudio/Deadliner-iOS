import SwiftUI

struct CircularWidgetView: View {
    let entry: DeadlinerEntry

    private var urgentProportion: Double {
        guard entry.remainingCount > 0 else { return 0 }
        return Double(entry.urgentCount) / Double(entry.remainingCount)
    }

    var body: some View {
        Gauge(value: urgentProportion) {
            Circle().frame(width: 2, height: 2)
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text("\(entry.remainingCount)")
                    .font(.system(size: 22, weight: .bold).monospaced())
                Text("\(entry.totalActiveCount)")
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}
