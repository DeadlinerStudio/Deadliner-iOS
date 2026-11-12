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
        GeometryReader { proxy in
            let breakpoint = AppLayoutBreakpoint(width: proxy.size.width)
            let usesColumns = breakpoint.isWide && !typeSize.isAccessibilitySize
            Group {
                if usesColumns {
                    wideLayout(breakpoint: breakpoint)
                } else {
                    overviewColumn {
                        calendarCards
                        taskCard
                        trendCard
                        reviewCard
                    }
                    .onScrollGeometryChange(for: CGFloat.self) {
                        max(0, $0.contentOffset.y + $0.contentInsets.top)
                    } action: { _, offset in
                        onScrollProgressChange?(min(max(offset / 120, 0), 1))
                    }
                }
            }
            .onAppear {
                if usesColumns { onScrollProgressChange?(0) }
            }
            .onChange(of: usesColumns) { _, _ in
                onScrollProgressChange?(0)
            }
        }
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
        .onAppear { onMonthTitleChange?(viewModel.monthTitle, viewModel.monthSubtitle) }
        .onChange(of: viewModel.selectedMonth) { onMonthTitleChange?(viewModel.monthTitle, viewModel.monthSubtitle) }
        .onChange(of: scenePhase) { if scenePhase == .active { viewModel.refreshForClockChange() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in viewModel.refreshForClockChange() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in viewModel.refreshForClockChange() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in viewModel.refreshForClockChange() }
    }
    private func wideLayout(breakpoint: AppLayoutBreakpoint) -> some View {
        HStack(alignment: .top, spacing: 16) {
            overviewColumn(horizontalPadding: 0) { calendarCards }
            overviewColumn(horizontalPadding: 0) {
                taskCard
                trendCard
                if breakpoint != .extraLarge { reviewCard }
            }
            if breakpoint == .extraLarge {
                overviewColumn(horizontalPadding: 0) { reviewCard }
            }
        }
        .padding(.horizontal, 16)
    }

    private func overviewColumn<Content: View>(horizontalPadding: CGFloat = 16, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 16, content: content)
                .frame(maxWidth: 760)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deadlinerScrollEdgeEffect()
    }

    private var calendarCards: some View {
        VStack(spacing: 16) {
            OverviewMonthCalendar(model: viewModel)
            managementCards
        }
    }

    private var taskCard: some View {
        VStack(spacing: 16) {
            NavigationLink { OverviewTaskDetail(model: viewModel) } label: {
                OverviewTaskResultCard(model: viewModel)
            }
            .buttonStyle(.plain)
            if let error = viewModel.monthError {
                OverviewFailureView(message: error, retry: viewModel.loadData)
            }
        }
    }

    private var trendCard: some View {
        NavigationLink { OverviewTrendDetail(model: viewModel) } label: {
            OverviewTrendPreview(model: viewModel)
        }
        .buttonStyle(.plain)
    }

    private var reviewCard: some View {
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
