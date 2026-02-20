//
//  HomeView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct HomeView: View {
    let playerViewModel: PlayerViewModel
    @StateObject private var viewModel: HomeViewModel
    @State private var isPlayerPresented = false
    @State private var hasRestoredPlayback = false

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
                } else {
                    chapterList
                }
            }
            .navigationTitle("Quran")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    reciterMenu
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
        .safeAreaInset(edge: .bottom) {
            HomeMiniPlayerContainer(
                playerViewModel: playerViewModel,
                isPlayerPresented: $isPlayerPresented
            )
        }
        .onChange(of: viewModel.selectedReciterID) { _, _ in
            guard let reciter = viewModel.selectedReciter else { return }
            playerViewModel.updateReciter(reciter)
        }
    }

    private var chapterList: some View {
        List(viewModel.chapters) { chapter in
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
        .padding(.bottom, 100)
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
