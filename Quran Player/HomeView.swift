//
//  HomeView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.isSearching) private var isSearching
    let playerViewModel: PlayerViewModel
    @StateObject private var viewModel: HomeViewModel
    @State private var isPlayerPresented = false
    @State private var hasRestoredPlayback = false
    @State private var chapterSearchText = ""
    @State private var isChapterSearchPresented = false

    @MainActor
    init(playerViewModel: PlayerViewModel, viewModel: HomeViewModel? = nil) {
        self.playerViewModel = playerViewModel
        _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.chapters.isEmpty {
                    ProgressView("Loading Quran")
                } else if let errorMessage = viewModel.errorMessage, viewModel.chapters.isEmpty {
                    ContentUnavailableView(
                        "Could not load Quran",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if filteredChapters.isEmpty {
                    ContentUnavailableView(
                        "No matching chapter",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different chapter name or number.")
                    )
                } else {
                    chapterList
                }
            }
            .navigationTitle("Quran")
            .searchable(
                text: $chapterSearchText,
                isPresented: $isChapterSearchPresented,
                prompt: "Search chapters"
            )
            .toolbar {
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
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.nameSimple)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(chapter.translatedName.name) - \(chapter.versesCount) verses")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(chapter.nameArabic)
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.bottom, filteredChapters.last == chapter ? 100 : 0)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedReciter == nil)
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.load()
            if let reciterID = playerViewModel.reciter?.id {
                viewModel.selectedReciterID = reciterID
            }
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

    private var shouldShowMiniPlayer: Bool {
        !isChapterSearchPresented && !isSearching
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
