//
//  HomeView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct HomeView: View {
    private enum BrowseFilter: String, CaseIterable, Identifiable {
        case chapters = "Chapters"
        case juz = "Juz"

        var id: String { rawValue }

        var searchPrompt: String {
            switch self {
            case .chapters:
                return "Search chapters"
            case .juz:
                return "Search juz"
            }
        }
    }

    private struct JuzBrowseItem: Identifiable, Hashable {
        let id: Int
        let startChapter: QuranChapter
        let endChapter: QuranChapter
    }

    private static let juzChapterRanges: [ClosedRange<Int>] = [
        1...2, 2...2, 2...3, 3...4, 4...4, 4...5, 5...6, 6...7, 7...8, 8...9,
        9...11, 11...12, 12...14, 15...16, 17...18, 18...20, 21...22, 23...25, 25...27, 27...29,
        29...33, 33...36, 36...39, 39...41, 41...45, 46...51, 51...57, 58...66, 67...77, 78...114
    ]

    @Environment(\.isSearching) private var isSearching
    let playerViewModel: PlayerViewModel
    @StateObject private var viewModel: HomeViewModel
    @State private var isPlayerPresented = false
    @State private var hasRestoredPlayback = false
    @State private var chapterSearchText = ""
    @State private var isChapterSearchPresented = false
    @State private var backgroundFlowProgress = false
    @State private var browseFilter: BrowseFilter = .chapters
    @State private var hasRunEntranceAnimation = false
    @State private var hasShownList = false
    @State private var hasShownMiniPlayer = false

    @MainActor
    init(playerViewModel: PlayerViewModel, viewModel: HomeViewModel? = nil) {
        self.playerViewModel = playerViewModel
        _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                animatedTrendingBackground
                    .ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.chapters.isEmpty {
                        ProgressView("Loading Quran")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.chapters.isEmpty {
                        ContentUnavailableView(
                            "Could not load Quran",
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isFilteredContentEmpty {
                        ContentUnavailableView(
                            browseFilter == .chapters ? "No matching chapter" : "No matching juz",
                            systemImage: "magnifyingglass",
                            description: Text(
                                browseFilter == .chapters
                                    ? "Try a different chapter name or number."
                                    : "Try a different juz number."
                            )
                        )
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Group {
                            if browseFilter == .chapters {
                                chapterList
                            } else {
                                juzList
                            }
                        }
                        .opacity(hasShownList ? 1 : 0)
                        .offset(y: hasShownList ? 0 : 24)
                    }
                }
            }
            .navigationTitle("Quran")
            .searchable(
                text: $chapterSearchText,
                isPresented: $isChapterSearchPresented,
                prompt: browseFilter.searchPrompt
            )
            .tint(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    browseFilterMenu
                }

                ToolbarItem(placement: .topBarTrailing) {
                    reciterMenu
                }
            }
            .safeAreaInset(edge: .bottom) {
                if shouldShowMiniPlayer {
                    HomeMiniPlayerContainer(
                        playerViewModel: playerViewModel,
                        isPlayerPresented: $isPlayerPresented
                    )
                    .opacity(hasShownMiniPlayer ? 1 : 0)
                    .offset(y: hasShownMiniPlayer ? 0 : 32)
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()

            if !hasRestoredPlayback {
                playerViewModel.restoreSessionIfPossible(
                    chapters: viewModel.chapters,
                    reciters: viewModel.reciters
                )
                if let reciterID = playerViewModel.reciter?.id {
                    viewModel.selectedReciterID = reciterID
                }
                hasRestoredPlayback = true
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerView()
                .environmentObject(playerViewModel)
        }
        .onChange(of: viewModel.selectedReciterID) { _, _ in
            guard let reciter = viewModel.selectedReciter else { return }
            playerViewModel.updateReciter(reciter)
        }
        .onChange(of: browseFilter) { _, _ in
            chapterSearchText = ""
            isChapterSearchPresented = false
        }
        .onAppear {
            startBackgroundAnimation()
            if !viewModel.chapters.isEmpty || viewModel.errorMessage != nil {
                runEntranceAnimationIfNeeded()
            }
        }
        .onChange(of: viewModel.chapters) { _, chapters in
            if !chapters.isEmpty {
                runEntranceAnimationIfNeeded()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, errorMessage in
            if errorMessage != nil {
                runEntranceAnimationIfNeeded()
            }
        }
    }

    private var chapterList: some View {
        List(filteredChapters) { chapter in
            Button {
                guard let reciter = viewModel.selectedReciter else { return }
                playerViewModel.startPlayback(
                    chapter: chapter,
                    chapters: viewModel.chapters,
                    reciter: reciter
                )
                isPlayerPresented = true
            } label: {
                HStack(spacing: 14) {
                    Text("\(chapter.id)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.nameSimple)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("\(chapter.translatedName.name) - \(chapter.versesCount) verses")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Text(chapter.nameArabic)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.bottom, filteredChapters.last == chapter ? 100 : 0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(.white.opacity(0.12))
            .buttonStyle(.plain)
            .disabled(viewModel.selectedReciter == nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.load()
            if let reciterID = playerViewModel.reciter?.id {
                viewModel.selectedReciterID = reciterID
            }
        }
    }

    private var juzList: some View {
        List(filteredJuzItems) { juzItem in
            Button {
                guard let reciter = viewModel.selectedReciter else { return }
                playerViewModel.startPlayback(
                    chapter: juzItem.startChapter,
                    chapters: viewModel.chapters,
                    reciter: reciter
                )
                isPlayerPresented = true
            } label: {
                HStack(spacing: 14) {
                    Text("\(juzItem.id)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Juz \(juzItem.id)")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(juzSubtitle(for: juzItem))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Text(juzItem.startChapter.nameArabic)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.bottom, filteredJuzItems.last == juzItem ? 100 : 0)
            }
            .listRowBackground(Color.white.opacity(0.08))
            .listRowSeparatorTint(.white.opacity(0.12))
            .buttonStyle(.plain)
            .disabled(viewModel.selectedReciter == nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.load()
            if let reciterID = playerViewModel.reciter?.id {
                viewModel.selectedReciterID = reciterID
            }
        }
    }

    private var browseFilterMenu: some View {
        Menu {
            ForEach(BrowseFilter.allCases) { filter in
                Button {
                    browseFilter = filter
                } label: {
                    if browseFilter == filter {
                        Label(filter.rawValue, systemImage: "checkmark")
                    } else {
                        Text(filter.rawValue)
                    }
                }
            }
        } label: {
            Label(browseFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var reciterMenu: some View {
        if viewModel.reciters.isEmpty {
            EmptyView()
        } else {
            Menu {
                ForEach(viewModel.reciters) { reciter in
                    Button {
                        viewModel.selectedReciterID = reciter.id
                    } label: {
                        HStack {
                            Text(reciter.displayName)
                            if viewModel.selectedReciterID == reciter.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "music.mic")
            }
        }
    }

    private var filteredChapters: [QuranChapter] {
        let query = chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.chapters }

        return viewModel.chapters.filter { chapter in
            if "\(chapter.id)".contains(query) {
                return true
            }

            if chapter.nameSimple.localizedCaseInsensitiveContains(query) {
                return true
            }

            if chapter.translatedName.name.localizedCaseInsensitiveContains(query) {
                return true
            }

            if chapter.nameArabic.contains(query) {
                return true
            }

            return false
        }
    }

    private var allJuzItems: [JuzBrowseItem] {
        Self.juzChapterRanges.enumerated().compactMap { offset, range in
            guard let startChapter = viewModel.chapters.first(where: { $0.id == range.lowerBound }) else {
                return nil
            }
            let endChapter = viewModel.chapters.first(where: { $0.id == range.upperBound }) ?? startChapter
            return JuzBrowseItem(id: offset + 1, startChapter: startChapter, endChapter: endChapter)
        }
    }

    private var filteredJuzItems: [JuzBrowseItem] {
        let query = chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allJuzItems }

        return allJuzItems.filter { juzItem in
            if "\(juzItem.id)".contains(query) { return true }
            if "juz \(juzItem.id)".localizedCaseInsensitiveContains(query) { return true }
            if juzItem.startChapter.nameSimple.localizedCaseInsensitiveContains(query) { return true }
            if juzItem.endChapter.nameSimple.localizedCaseInsensitiveContains(query) { return true }
            if juzItem.startChapter.nameArabic.contains(query) { return true }
            if juzItem.endChapter.nameArabic.contains(query) { return true }
            return false
        }
    }

    private var isFilteredContentEmpty: Bool {
        switch browseFilter {
        case .chapters:
            return filteredChapters.isEmpty
        case .juz:
            return filteredJuzItems.isEmpty
        }
    }

    private func juzSubtitle(for juzItem: JuzBrowseItem) -> String {
        if juzItem.startChapter.id == juzItem.endChapter.id {
            return "Surah \(juzItem.startChapter.id) \(juzItem.startChapter.nameSimple)"
        }

        return "Surah \(juzItem.startChapter.id) to \(juzItem.endChapter.id)"
    }

    private var shouldShowMiniPlayer: Bool {
        !isChapterSearchPresented && !isSearching
    }

    private var animatedTrendingBackground: some View {
        let flowStart = UnitPoint(x: 0.5, y: backgroundFlowProgress ? -0.15 : 1.15)
        let flowEnd = UnitPoint(x: 0.5, y: backgroundFlowProgress ? 0.85 : 2.15)

        return ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.11, blue: 0.20),
                    Color(red: 0.06, green: 0.15, blue: 0.11),
                    Color(red: 0.09, green: 0.10, blue: 0.18),
                    Color(red: 0.12, green: 0.12, blue: 0.14)
                ],
                startPoint: flowStart,
                endPoint: flowEnd
            )
            .opacity(0.45)
            .blur(radius: 36)
        }
    }

    private func startBackgroundAnimation() {
        guard !backgroundFlowProgress else { return }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
            backgroundFlowProgress = true
        }
    }

    private func runEntranceAnimationIfNeeded() {
        guard !hasRunEntranceAnimation else { return }
        hasRunEntranceAnimation = true

        withAnimation(.easeOut(duration: 0.38)) {
            hasShownList = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                hasShownMiniPlayer = true
            }
        }
    }
}

private struct HomeMiniPlayerContainer: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    @Binding var isPlayerPresented: Bool

    var body: some View {
        Group {
            if playerViewModel.isSessionActive {
                MiniPlayerBar {
                    isPlayerPresented = true
                }
                .environmentObject(playerViewModel)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .onChange(of: playerViewModel.isSessionActive) { _, isActive in
            if !isActive {
                isPlayerPresented = false
            }
        }
    }
}
