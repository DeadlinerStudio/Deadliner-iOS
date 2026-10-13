import SwiftUI
import Shared

struct OverviewView: View {
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    var compactLayoutProgress: CGFloat? = nil
    var onMonthTitleChange: ((String, String) -> Void)? = nil
    @StateObject private var viewModel = OverviewViewModel()
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var archiveQuery = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OverviewMonthCalendar(model: viewModel)
                managementCards
                NavigationLink { OverviewTaskDetail(model: viewModel) } label: { OverviewTaskResultCard(model: viewModel) }
                    .buttonStyle(.plain)
                if let error = viewModel.monthError { OverviewFailureView(message: error, retry: viewModel.loadData) }
                NavigationLink { OverviewTrendDetail(model: viewModel) } label: { OverviewTrendPreview(model: viewModel) }
                    .buttonStyle(.plain)
                OverviewSurface {
                    if viewModel.monthlyAnalysis != nil {
                        NavigationLink { OverviewReviewDetail(model: viewModel) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                reviewHeading
                                OverviewInsightContent(model: viewModel)
                                reviewFooter
                            }
                        }.buttonStyle(.plain)
                    } else {
                        NavigationLink { OverviewReviewDetail(model: viewModel) } label: { reviewHeading }.buttonStyle(.plain)
                        OverviewInsightContent(model: viewModel)
                        NavigationLink { OverviewReviewDetail(model: viewModel) } label: { reviewFooter }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .deadlinerScrollEdgeEffect()
        .navigationTitle(viewModel.monthTitle)
        .navigationSubtitle(viewModel.monthSubtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { viewModel.changeMonth(by: -1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("上个月")
                Button { viewModel.changeMonth(by: 1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("下个月").disabled(!viewModel.canGoForward)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { _, offset in
            onScrollProgressChange?(min(max(offset / 120, 0), 1))
        }
        .onAppear { onMonthTitleChange?(viewModel.monthTitle, viewModel.monthSubtitle) }
        .onChange(of: viewModel.selectedMonth) { onMonthTitleChange?(viewModel.monthTitle, viewModel.monthSubtitle) }
        .onChange(of: scenePhase) { if scenePhase == .active { viewModel.refreshForClockChange() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in viewModel.refreshForClockChange() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in viewModel.refreshForClockChange() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in viewModel.refreshForClockChange() }
    }
    private var reviewHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverviewCardHeading(title: "月度复盘", disclosure: true)
            Text(viewModel.reviewMonthLabel).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    private var reviewFooter: some View {
        Text("查看完整复盘、活动分布与分享").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
    private var managementCards: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize { HStack(spacing: 16) { focusCard.frame(minWidth: 130); archiveCard.frame(minWidth: 130) } }
            VStack(spacing: 16) { focusCard; archiveCard }
        }
    }
    private var focusCard: some View {
        NavigationLink { OverviewFocusManagement(model: viewModel) } label: {
            OverviewSurface {
                OverviewCardHeading(title: "专注管理", disclosure: true)
                if viewModel.focusLoading { ProgressView() }
                else if viewModel.focusError != nil { Text("暂不可用").font(.subheadline).foregroundStyle(.secondary) }
                else { Text(FocusTimerFormatting.duration(viewModel.focus?.today.totalDurationSeconds ?? 0)).font(.title2.bold()).monospacedDigit() }
            }
        }.buttonStyle(.plain)
    }
    private var archiveCard: some View {
        NavigationLink { ArchiveView(query: $archiveQuery).navigationTitle("归档").background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea()) } label: {
            OverviewSurface {
                OverviewCardHeading(title: "归档", disclosure: true)
                if viewModel.monthLoading { ProgressView() }
                else if viewModel.monthError != nil { Text("暂不可用").font(.subheadline).foregroundStyle(.secondary) }
                else { Text("\(viewModel.monthState?.archivedCount ?? 0) 项").font(.title2.bold()).monospacedDigit() }
            }
        }.buttonStyle(.plain)
    }
}
