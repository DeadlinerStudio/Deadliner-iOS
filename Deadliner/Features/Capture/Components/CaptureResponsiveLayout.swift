import SwiftUI

struct CaptureResponsiveLayout<Composer: View, Header: View, Empty: View, Note: View>: View {
    let items: [CaptureInboxItem]
    let selectionMode: Bool
    let composer: Composer
    let header: Header
    let empty: Empty
    let note: (CaptureInboxItem) -> Note
    let onScrollProgressChange: ((CGFloat) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let breakpoint = AppLayoutBreakpoint(width: proxy.size.width)
            Group {
                if breakpoint.isWide {
                    HStack(alignment: .top, spacing: 16) {
                        if !selectionMode {
                            ScrollView {
                                composer.padding(.vertical, 12)
                            }
                            .frame(width: breakpoint.captureComposerWidth(availableWidth: proxy.size.width))
                            .deadlinerScrollEdgeEffect(forceImmersive: false)
                        }
                        notesScrollView(breakpoint: breakpoint)
                    }
                    .padding(.horizontal, 16)
                } else if breakpoint == .medium {
                    ScrollView {
                        VStack(spacing: 16) {
                            if !selectionMode {
                                composer.frame(maxWidth: 720).padding(.top, 12)
                            }
                            notesGrid(breakpoint: breakpoint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .deadlinerScrollEdgeEffect(forceImmersive: false)
                } else {
                    compactList
                }
            }
            .onAppear {
                if breakpoint != .small { onScrollProgressChange?(0) }
            }
            .onChange(of: breakpoint) { _, _ in
                // Independent columns have no meaningful shared scroll distance.
                onScrollProgressChange?(0)
            }
        }
    }

    private var compactList: some View {
        List {
            composer
            if items.isEmpty {
                empty
            } else {
                header
                ForEach(items) { note($0) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .deadlinerScrollEdgeEffect(forceImmersive: false)
        .onScrollGeometryChange(for: CGFloat.self) {
            max(0, $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, offset in
            onScrollProgressChange?(min(max(offset / 120, 0), 1))
        }
    }

    private func notesScrollView(breakpoint: AppLayoutBreakpoint) -> some View {
        ScrollView {
            notesGrid(breakpoint: breakpoint)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deadlinerScrollEdgeEffect(forceImmersive: false)
    }

    private func notesGrid(breakpoint: AppLayoutBreakpoint) -> some View {
        VStack(spacing: 12) {
            if items.isEmpty {
                empty
            } else {
                header
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: breakpoint.captureColumns),
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(items) { note($0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
