//
//  HomeView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import AdaptyUI
import SwiftUI

struct HomeView: View {
    @Environment(\.isSearching) private var isSearching
    let playerViewModel: PlayerViewModel
    @StateObject private var viewModel: HomeViewModel
    @StateObject private var paywallManager = PaywallManager()
    @State private var isPlayerPresented = false
    @State private var hasRestoredPlayback = false
    @State private var chapterSearchText = ""
    @State private var isChapterSearchPresented = false
    @State private var backgroundFlowProgress = false
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
                            "No matching chapter",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different chapter name or number.")
                        )
                        .foregroundStyle(.white.opacity(0.9))
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
            .tint(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    proButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    reciterMenu
                }
            }
            .paywall(
                isPresented: $paywallManager.isPresented,
                paywallConfiguration: paywallManager.paywallConfiguration,
                didFailPurchase: { _, error in
                    paywallManager.handleFailedPurchase(error)
                },
                didFinishRestore: { _ in },
                didFailRestore: { error in
                    paywallManager.handleFailedRestore(error)
                },
                didFailRendering: { error in
                    paywallManager.handleFailedRendering(error)
                }
            )
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
        .alert(item: $paywallManager.presentationError) { paywallError in
            Alert(
                title: Text("Paywall Error"),
                message: Text(paywallError.message),
                dismissButton: .default(Text("OK"))
            )
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

    private var isFilteredContentEmpty: Bool {
        filteredChapters.isEmpty
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
