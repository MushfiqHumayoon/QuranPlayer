//
//  HomeView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.isSearching) private var isSearching
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var paywallManager: PaywallManager
    let playerViewModel: PlayerViewModel
    @StateObject private var viewModel: HomeViewModel
    @State private var isPlayerPresented = false
    @State private var hasRestoredPlayback = false
    @State private var chapterSearchText = ""
    @State private var isChapterSearchPresented = false
    @State private var hasRunEntranceAnimation = false
    @State private var hasShownList = false
    @State private var hasShownMiniPlayer = false
    @State private var isSettingsPresented = false

    @MainActor
    init(playerViewModel: PlayerViewModel, viewModel: HomeViewModel? = nil) {
        self.playerViewModel = playerViewModel
        _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground(colorScheme: colorScheme)
                    .ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.chapters.isEmpty {
                        ProgressView("Loading Quran")
                            .tint(AppTheme.primaryText(colorScheme))
                            .foregroundStyle(AppTheme.primaryText(colorScheme))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.chapters.isEmpty {
                        ContentUnavailableView(
                            "Could not load Quran",
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isFilteredContentEmpty {
                        ContentUnavailableView(
                            "No matching chapter",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different chapter name or number.")
                        )
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        chapterList
                            .opacity(hasShownList ? 1 : 0)
                            .offset(y: hasShownList ? 0 : 24)
                    }
                }
            }
            .navigationTitle("Quran")
            .searchable(
                text: $chapterSearchText,
                isPresented: $isChapterSearchPresented,
                prompt: "Search chapters"
            )
            .tint(AppTheme.tintColor(colorScheme))
            .toolbar {
                if !paywallManager.isSubscribed {
                    ToolbarItem(placement: .topBarLeading) {
                        proButton
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(viewModel: viewModel)
                .environmentObject(paywallManager)
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerView()
                .environmentObject(playerViewModel)
                .environmentObject(paywallManager)
        }
        .onChange(of: viewModel.selectedReciterID) { _, _ in
            guard let reciter = viewModel.selectedReciter else { return }
            playerViewModel.updateReciter(reciter)
        }
        .onAppear {
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
                        .foregroundStyle(AppTheme.tertiaryText(colorScheme))
                        .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.nameSimple)
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText(colorScheme))

                        Text("\(chapter.translatedName.name) - \(chapter.versesCount) verses")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText(colorScheme))
                    }

                    Spacer()

                    Text(chapter.nameArabic)
                        .font(.title3)
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.bottom, filteredChapters.last == chapter ? 100 : 0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(AppTheme.separator(colorScheme))
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

    private var proButton: some View {
        Button {
            paywallManager.presentPaywall()
        } label: {
            Text("Pro")
                .font(.caption.weight(.bold))
                .kerning(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.clear)
        }
        .disabled(paywallManager.isLoading)
        .opacity(paywallManager.isLoading ? 0.7 : 1)
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

    private var isFilteredContentEmpty: Bool {
        filteredChapters.isEmpty
    }

    private var shouldShowMiniPlayer: Bool {
        !isChapterSearchPresented && !isSearching
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
