//
//  PlayerView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: PlayerViewModel

    @State private var scrubTime: Double = 0
    @State private var isEditingSlider = false
    @State private var isOptionsSheetPresented = false

    var body: some View {
        Group {
            if let chapter = viewModel.currentChapter {
                playerBody(chapter: chapter)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onChange(of: viewModel.currentTime) { _, newValue in
            if !isEditingSlider {
                scrubTime = newValue
            }
        }
        .sheet(isPresented: $isOptionsSheetPresented) {
            PlayerOptionsSheet()
                .environmentObject(viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Playback Error", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func playerBody(chapter: QuranChapter) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.22, blue: 0.19),
                    Color(red: 0.16, green: 0.26, blue: 0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer()
                artwork
                metadata(chapter: chapter)
                progressSection
                controls(chapter: chapter)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 28)

            if viewModel.isLoadingAudio {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Playing Quran")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(viewModel.reciter?.reciterName ?? "Quran")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isOptionsSheetPresented = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.25),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(maxWidth: 340)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 14)
    }

    private func metadata(chapter: QuranChapter) -> some View {
        VStack(spacing: 8) {
            Text(chapter.nameSimple)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(chapter.nameArabic)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.92))

            Text("Chapter \(chapter.id) - \(chapter.translatedName.name)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            if viewModel.isDownloadingCurrentChapter {
                Label("Downloading for offline playback", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            } else if viewModel.isChapterCached {
                Label("Available offline", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }

            if let sleepTimerDisplayText = viewModel.sleepTimerDisplayText {
                Text("Sleep in \(sleepTimerDisplayText)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: {
                        isEditingSlider ? scrubTime : viewModel.currentTime
                    },
                    set: { newValue in
                        scrubTime = newValue
                    }
                ),
                in: 0...max(viewModel.duration, 1),
                onEditingChanged: { isEditing in
                    isEditingSlider = isEditing
                    if !isEditing {
                        viewModel.seek(to: scrubTime)
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(formatTime(viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func controls(chapter: QuranChapter) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 34) {
                Button(action: viewModel.playPreviousChapter) {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(!viewModel.canGoToPreviousChapter)

                Button(action: viewModel.skipBackward) {
                    Image(systemName: "gobackward.15")
                }

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70))
                }

                Button(action: viewModel.skipForward) {
                    Image(systemName: "goforward.15")
                }

                Button(action: viewModel.playNextChapter) {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!viewModel.canGoToNextChapter)
            }
            .font(.title2)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .symbolRenderingMode(.hierarchical)
            .opacity(viewModel.isLoadingAudio ? 0.6 : 1)
            .disabled(viewModel.isLoadingAudio)

            Text("\(chapter.versesCount) verses")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "00:00" }
        let clamped = max(0, Int(seconds))
        let minutes = clamped / 60
        let remainingSeconds = clamped % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct PlayerOptionsSheet: View {
    @EnvironmentObject private var viewModel: PlayerViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Offline") {
                    if viewModel.isChapterCached {
                        Label("Current chapter is downloaded", systemImage: "checkmark.circle.fill")
                    } else if viewModel.isDownloadingCurrentChapter {
                        Label("Downloading...", systemImage: "arrow.down.circle")
                    } else {
                        Button {
                            viewModel.downloadCurrentChapterForOffline()
                        } label: {
                            Label("Download Current Chapter", systemImage: "arrow.down.circle")
                        }
                    }
                }

                Section("Sleep Timer") {
                    ForEach(SleepTimerPreset.allCases) { preset in
                        Button(preset.title) {
                            viewModel.setSleepTimer(preset)
                        }
                    }

                    if viewModel.hasActiveSleepTimer {
                        if let sleepTimerDisplayText = viewModel.sleepTimerDisplayText {
                            Text("Remaining: \(sleepTimerDisplayText)")
                                .foregroundStyle(.secondary)
                        }

                        Button("Cancel Sleep Timer", role: .destructive) {
                            viewModel.cancelSleepTimer()
                        }
                    }
                }
            }
            .navigationTitle("Player Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
