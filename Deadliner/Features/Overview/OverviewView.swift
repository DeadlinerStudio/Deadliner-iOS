//
//  OverviewView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct OverviewView: View {
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    
    @StateObject private var viewModel = OverviewViewModel()
    @State private var selectedTabIndex = 0
    
    var body: some View {
        contentView
        .background(Color.clear)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTabIndex == 2 {
                    Button {
                        // TODO: Share dashboard
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                } else {
                    EditButton()
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在加载数据...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private var contentView: some View {
        List {
            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.top, 40)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if selectedTabIndex == 0 {
                        ForEach(Array(viewModel.overviewCardOrder.enumerated()), id: \.element) { index, cardId in
                            FloatUpRow(index: index) {
                                OverviewStatsCard(viewModel: viewModel, cardId: cardId)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove { from, to in
                            viewModel.onCardMove(tab: "OVERVIEW", from: from.first!, to: to)
                        }
                    } else if selectedTabIndex == 1 {
                        ForEach(Array(viewModel.trendCardOrder.enumerated()), id: \.element) { index, cardId in
                            FloatUpRow(index: index) {
                                TrendAnalysisCard(viewModel: viewModel, cardId: cardId)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove { from, to in
                            viewModel.onCardMove(tab: "TREND", from: from.first!, to: to)
                        }
                    } else {
                        // DashboardSection
                        DashboardSection(
                            metrics: viewModel.metrics,
                            dailyStats: viewModel.lastMonthDailyStats,
                            lastMonthName: viewModel.lastMonthName,
                            analysis: viewModel.monthlyAnalysis,
                            isAnalyzing: viewModel.isAnalyzing
                        )
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                // 统一与 HomeView 一致的 Picker 边距
                Picker("", selection: $selectedTabIndex) {
                    Text("总览").tag(0)
                    Text("趋势").tag(1)
                    Text("上月").tag(2)
                }
                .pickerStyle(.segmented)
                .glassEffect()
                .textCase(nil)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            let p = min(max(newValue / 120, 0), 1)
            onScrollProgressChange?(p)
        }
    }
}
