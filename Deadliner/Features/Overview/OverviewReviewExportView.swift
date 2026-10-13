import SwiftUI
import Shared
import PhotosUI
import Photos

struct OverviewReviewExportView: View {
    @ObservedObject var model: OverviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var darkText = true
    @State private var photo: PhotosPickerItem?
    @State private var background: UIImage?
    @State private var rendered: UIImage?
    @State private var showPreview = false
    @State private var sharePresented = false
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("样式") {
                    Toggle("深色文字", isOn: $darkText)
                    PhotosPicker("选择背景图", selection: $photo, matching: .images)
                    if background != nil { Button("移除背景图") { background = nil; photo = nil } }
                }
                Section("预览") {
                    poster.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 20))
                    Button("查看完整预览") { render(); showPreview = rendered != nil }
                }
                Section {
                    Button { render(); sharePresented = rendered != nil } label: { Label("系统分享", systemImage: "square.and.arrow.up") }
                    Button { save() } label: { Label("保存到图库", systemImage: "photo.badge.arrow.down") }.disabled(saving)
                    if saving { ProgressView() }
                }
            }
            .navigationTitle("分享月度复盘").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
        .onChange(of: photo) {
            _Concurrency.Task {
                if let data = try? await photo?.loadTransferable(type: Data.self) { background = UIImage(data: data) }
            }
        }
        .sheet(isPresented: $sharePresented) { if let rendered { ActivityView(activityItems: [rendered]) } }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ScrollView { if let rendered { Image(uiImage: rendered).resizable().scaledToFit() } }
                    .navigationTitle("复盘预览").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showPreview = false } } }
            }
        }
        .alert("月度复盘", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("完成") { message = nil } } message: { Text(message ?? "") }
    }
    private var poster: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Deadliner · 月度复盘").font(.headline)
            Text(model.reviewMonthLabel).font(.largeTitle.bold())
            if let analysis = model.monthlyAnalysis {
                Text(analysis.summary).font(.body).fixedSize(horizontal: false, vertical: true).lineSpacing(5)
                OverviewKeywordLayout { ForEach(Array(analysis.keywords.enumerated()), id: \.offset) { _, keyword in Text(keyword).font(.caption).padding(8).background((darkText ? Color.black : .white).opacity(0.08), in: Capsule()) } }
            } else { Text(model.insightError ?? "AI 洞察尚未生成").font(.subheadline) }
            Divider()
            ForEach(model.metrics) { metric in HStack { Text(metric.label); Spacer(); Text(metric.value).bold() } }
            Text("活动分布 · 每日完成任务").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<((OverviewPeriod.calendar.component(.weekday, from: OverviewPeriod.shifted(Date(), by: -1)) + 5) % 7), id: \.self) { _ in Color.clear.frame(height: 28) }
                ForEach(model.lastMonthDailyStats) { day in
                    Text(day.date).font(.caption2).frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.green.opacity(day.completedCount == 0 ? 0.08 : min(0.8, 0.2 + Double(day.completedCount) * 0.1)), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            if let focus = model.focus?.lastMonth.current.summary {
                HStack { Text("上月专注"); Spacer(); Text(FocusTimerFormatting.duration(focus.totalDurationSeconds)).bold() }
            }
            Text("指标按截止月份统计，活动按完成日期统计。AI 洞察为该月份已保存结果。").font(.caption)
        }
        .foregroundStyle(darkText ? Color.black : .white)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                if let background { Image(uiImage: background).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() }
                else { LinearGradient(colors: darkText ? [Color(red: 0.91, green: 0.94, blue: 1), .white] : [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
        }
        .environment(\.colorScheme, darkText ? .light : .dark)
    }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: poster.frame(width: 390))
        renderer.scale = 3
        rendered = renderer.uiImage
        if rendered == nil { message = "无法生成预览，请重试" }
    }
    private func save() {
        render()
        guard let rendered else { return }
        saving = true
        _Concurrency.Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { saving = false; message = "请在系统设置中允许添加照片"; return }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: rendered) }
                message = "已保存到图库"
            } catch { message = "保存失败：\(error.localizedDescription)" }
            saving = false
        }
    }
}
