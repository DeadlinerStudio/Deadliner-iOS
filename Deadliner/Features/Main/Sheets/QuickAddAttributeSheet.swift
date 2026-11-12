import SwiftUI

enum QuickAddAttribute: String, Identifiable {
    case start, due, note, schedule, reminder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .start: return "开始时间"
        case .due: return "截止时间"
        case .note: return "备注"
        case .schedule: return "重复规则"
        case .reminder: return "提醒时间"
        }
    }
}

struct QuickAddAttributeSheet: View {
    let attribute: QuickAddAttribute
    let draft: QuickAddDraft
    @Binding var overrides: QuickAddOverrides
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var note = ""
    @State private var period = "DAILY"
    @State private var count = 1
    @State private var weekdays = 127

    var body: some View {
        NavigationStack {
            Form {
                switch attribute {
                case .start:
                    DatePicker("开始时间", selection: $date)
                    Button("移除开始时间", role: .destructive) { overrides.startAt = nil; dismiss() }
                case .due:
                    DatePicker("截止时间", selection: $date)
                    Button("移除截止时间", role: .destructive) {
                        overrides.dueAt = nil
                        overrides.removesDue = true
                        dismiss()
                    }
                case .note:
                    TextField("备注", text: $note, axis: .vertical).lineLimit(4...10)
                case .schedule:
                    Picker("周期", selection: $period) {
                        Text("每天").tag("DAILY")
                        Text("每周").tag("WEEKLY")
                        Text("每月").tag("MONTHLY")
                        Text("累计").tag("TOTAL")
                        Text("单次").tag("ONCE")
                        Text("艾宾浩斯").tag("EBBINGHAUS")
                    }
                    Stepper("目标 \(count) 次", value: $count, in: 1...999)
                    Section("执行日") {
                        ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { index, day in
                            Toggle("周" + day, isOn: Binding(
                                get: { weekdays & (1 << index) != 0 },
                                set: { value in
                                    if value { weekdays |= 1 << index }
                                    else { weekdays &= ~(1 << index) }
                                }))
                        }
                    }
                case .reminder:
                    DatePicker("提醒时间", selection: $date, displayedComponents: .hourAndMinute)
                    Button("移除提醒", role: .destructive) {
                        overrides.reminderTime = nil
                        overrides.removesReminder = true
                        dismiss()
                    }
                }
            }
            .navigationTitle(attribute.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit(); dismiss() }
                        .disabled(attribute == .schedule && weekdays == 0)
                }
            }
        }
        .onAppear {
            note = draft.note
            period = draft.period
            count = min(999, max(1, draft.targetCount))
            weekdays = draft.weekdaysMask
            if attribute == .start, let start = overrides.startAt { date = start }
            if attribute == .due, let raw = draft.dueAt, let parsed = DeadlineDateParser.safeParseOptional(raw) { date = parsed }
            if attribute == .reminder, let raw = draft.reminderTime {
                let parts = raw.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2, let parsed = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) { date = parsed }
            }
        }
    }

    private func commit() {
        switch attribute {
        case .start: overrides.startAt = date
        case .due:
            overrides.dueAt = date
            overrides.removesDue = false
        case .note: overrides.note = note
        case .schedule:
            overrides.removesSchedule = false
            overrides.period = period
            overrides.targetCount = count
            overrides.weekdaysMask = weekdays
        case .reminder:
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            overrides.reminderTime = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            overrides.removesReminder = false
        }
    }
}
