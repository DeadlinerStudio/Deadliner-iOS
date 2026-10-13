import SwiftUI
import Shared

struct OverviewTaskDetail: View {
    @ObservedObject var model: OverviewViewModel
    var body: some View {
        List {
            if model.isLoading { ProgressView().listRowBackground(Color.clear) }
            if let error = model.taskError { OverviewFailureView(message: error, retry: model.loadData) }
            if model.taskError == nil && !model.isLoading {
            ForEach(model.overviewCardOrder, id: \.self) { card in
                OverviewStatsCard(viewModel: model, cardId: card)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }.onMove { from, to in if let index = from.first { model.onCardMove(tab: "OVERVIEW", from: index, to: to) } }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).deadlinerScrollEdgeEffect()
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("任务统计").navigationSubtitle("今日概况、完成时段与任务状态")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }
}

struct OverviewTrendDetail: View {
    @ObservedObject var model: OverviewViewModel
    var body: some View {
        List {
            if let error = model.taskError { OverviewFailureView(message: error, retry: model.loadData) }
            if let error = model.focusError { OverviewFailureView(message: error, retry: model.loadData) }
            if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(model.trendCardOrder, id: \.self) { card in
                Group {
                    if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    else if card == .contributionHeatmap && model.contributionLoading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    else if card == .contributionHeatmap, let error = model.contributionError { OverviewFailureView(message: error, retry: model.loadData) }
                    else { TrendAnalysisCard(viewModel: model, cardId: card) }
                }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }.onMove { from, to in if let index = from.first { model.onCardMove(tab: "TREND", from: index, to: to) } }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).deadlinerScrollEdgeEffect()
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("趋势").navigationSubtitle("以今天为锚点")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }
}

struct OverviewReviewDetail: View {
    @ObservedObject var model: OverviewViewModel
    @State private var exportPresented = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OverviewSurface {
                    Text(model.reviewMonthLabel).font(.title2.bold())
                    Text("复盘指标按截止日期所属月份统计；活动图按实际完成日期统计。逾期指标沿用未完成计数，包含放弃任务。").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16)
                if let error = model.taskError { OverviewFailureView(message: error, retry: model.loadData).padding(.horizontal, 16) }
                OverviewSurface {
                    OverviewCardHeading(title: "AI 月度洞察")
                    OverviewInsightContent(model: model)
                }.padding(.horizontal, 16)
                if model.taskError == nil && !model.isLoading {
                DashboardSection(focus: model.focus?.lastMonth, metrics: model.metrics,
                    dailyStats: model.lastMonthDailyStats, lastMonthName: model.lastMonthName,
                    analysis: nil, isAnalyzing: false)
                }
            }.frame(maxWidth: 760).padding(.vertical, 8).frame(maxWidth: .infinity)
        }
        .deadlinerScrollEdgeEffect()
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("月度复盘").navigationSubtitle(model.reviewMonthLabel)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { exportPresented = true } label: { Label("分享", systemImage: "square.and.arrow.up") }
                .disabled(model.isLoading || model.taskError != nil)
        } }
        .sheet(isPresented: $exportPresented) { OverviewReviewExportView(model: model) }
    }
}
