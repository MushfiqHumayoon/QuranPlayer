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
    @State private var currentVerseOffscreenDirection: CurrentVerseJumpDirection?
    @State private var jumpToCurrentVerseRequestID = 0
    @State private var scrollToTopRequestID = 0
    @State private var backgroundFlowProgress = false

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
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 760

            ZStack {
                animatedTrendingBackground
                .ignoresSafeArea()

                VStack(spacing: isCompactHeight ? 12 : 18) {
                    header(chapter: chapter)
//                    artwork(maxWidth: isCompactHeight ? 210 : 300)
                    metadata(chapter: chapter)
                    versesSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                if viewModel.isLoadingAudio {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomPlaybackBar(chapter: chapter)
            }
            .onAppear {
                startBackgroundAnimation()
            }
        }
    }

    private func header(chapter: QuranChapter) -> some View {
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
                Text(chapter.nameSimple)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(chapter.nameArabic)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.92))
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

    private func artwork(maxWidth: CGFloat) -> some View {
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
            .frame(maxWidth: maxWidth)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 14)
    }

    private func metadata(chapter: QuranChapter) -> some View {
        VStack(spacing: 8) {
            Text(viewModel.reciter?.reciterName ?? "Quran")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
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

    private var versesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            versesSectionHeader
            versesSectionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.verses.isEmpty) { _, isEmpty in
            if isEmpty {
                currentVerseOffscreenDirection = nil
            }
        }
        .onChange(of: viewModel.currentChapter?.id) { _, _ in
            currentVerseOffscreenDirection = nil
            scrollToTopRequestID += 1
        }
    }

    private var versesSectionHeader: some View {
        HStack {
            Text("Verses")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            if let verseIndex = viewModel.currentVerseIndex, !viewModel.verses.isEmpty {
                HStack(spacing: 8) {
                    Text("Ayah \(verseIndex + 1)/\(viewModel.verses.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))

                    if let currentVerseOffscreenDirection {
                        Button {
                            jumpToCurrentVerseRequestID += 1
                        } label: {
                            Image(systemName: currentVerseOffscreenDirection.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var versesSectionContent: some View {
        if viewModel.verses.isEmpty {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    if viewModel.isLoadingVerses {
                        ProgressView("Loading verses")
                            .font(.caption)
                            .tint(.white)
                    } else {
                        Text("Verses unavailable for this chapter.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VerseLyricsList(
                verses: viewModel.verses,
                highlightedIndex: viewModel.currentVerseIndex,
                scrollToTopRequestID: scrollToTopRequestID,
                scrollToCurrentVerseRequestID: jumpToCurrentVerseRequestID,
                onVerseTap: { verseIndex in
                    isEditingSlider = false
                    viewModel.seek(toVerseIndex: verseIndex)
                    scrubTime = viewModel.currentTime
                },
                onCurrentVerseVisibilityChange: { direction in
                    currentVerseOffscreenDirection = direction
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func bottomPlaybackBar(chapter: QuranChapter) -> some View {
        VStack(spacing: 14) {
            progressSection
            controls(chapter: chapter)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Color.clear)
                .ignoresSafeArea(edges: .bottom)
        )
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

            Text("Chapter \(chapter.id) - \(chapter.translatedName.name) | \(chapter.versesCount) verses")
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
}

private struct VerseLyricsList: View {
    let verses: [QuranVerse]
    let highlightedIndex: Int?
    let scrollToTopRequestID: Int
    let scrollToCurrentVerseRequestID: Int
    let onVerseTap: (Int) -> Void
    let onCurrentVerseVisibilityChange: (CurrentVerseJumpDirection?) -> Void

    @State private var rowFramesByIndex: [Int: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero
    @State private var lastReportedDirection: CurrentVerseJumpDirection?
    @State private var lastHandledScrollToTopRequestID: Int?

    private let topAnchorID = "verse-list-top-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorID)

                    ForEach(verses.indices, id: \.self) { index in
                        VerseLyricsRow(
                            index: index,
                            verse: verses[index],
                            isCurrent: index == highlightedIndex
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onVerseTap(index)
                        }
                        .animation(.easeInOut(duration: 0.25), value: highlightedIndex)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: VerseRowFramePreferenceKey.self,
                                    value: [index: geometry.frame(in: .named("VerseLyricsScrollArea"))]
                                )
                            }
                        }
                        .id(verses[index].id)
                    }
                }
            }
            .coordinateSpace(name: "VerseLyricsScrollArea")
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: VerseViewportFramePreferenceKey.self,
                        value: geometry.frame(in: .named("VerseLyricsScrollArea"))
                    )
                }
            }
            .onPreferenceChange(VerseRowFramePreferenceKey.self) { value in
                rowFramesByIndex = value
                updateCurrentVerseDirection()
            }
            .onPreferenceChange(VerseViewportFramePreferenceKey.self) { value in
                viewportFrame = value
                updateCurrentVerseDirection()
            }
            .onAppear {
                handleScrollToTopRequest(proxy: proxy, animated: false)
                updateCurrentVerseDirection()
            }
            .onChange(of: highlightedIndex) { _, _ in
                updateCurrentVerseDirection()
            }
            .onChange(of: scrollToTopRequestID) { _, _ in
                handleScrollToTopRequest(proxy: proxy, animated: true)
            }
            .onChange(of: scrollToCurrentVerseRequestID) { _, _ in
                scrollToHighlightedVerse(proxy: proxy, animated: true)
                reportCurrentVerseDirection(nil)
            }
        }
        .onDisappear {
            reportCurrentVerseDirection(nil)
        }
    }

    private func scrollToHighlightedVerse(proxy: ScrollViewProxy, animated: Bool) {
        guard let highlightedIndex, verses.indices.contains(highlightedIndex) else { return }
        let verseID = verses[highlightedIndex].id

        if animated {
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(verseID, anchor: .center)
            }
        } else {
            proxy.scrollTo(verseID, anchor: .center)
        }
    }

    private func handleScrollToTopRequest(proxy: ScrollViewProxy, animated: Bool) {
        guard lastHandledScrollToTopRequestID != scrollToTopRequestID else { return }
        lastHandledScrollToTopRequestID = scrollToTopRequestID
        scrollToTop(proxy: proxy, animated: animated)
        reportCurrentVerseDirection(nil)
    }

    private func scrollToTop(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(topAnchorID, anchor: .top)
            }
        } else {
            proxy.scrollTo(topAnchorID, anchor: .top)
        }
    }

    private func updateCurrentVerseDirection() {
        guard let highlightedIndex else {
            reportCurrentVerseDirection(nil)
            return
        }

        guard let verseFrame = rowFramesByIndex[highlightedIndex], !viewportFrame.isEmpty else {
            reportCurrentVerseDirection(nil)
            return
        }

        let direction: CurrentVerseJumpDirection?
        if verseFrame.maxY < viewportFrame.minY {
            direction = .up
        } else if verseFrame.minY > viewportFrame.maxY {
            direction = .down
        } else {
            direction = nil
        }

        reportCurrentVerseDirection(direction)
    }

    private func reportCurrentVerseDirection(_ direction: CurrentVerseJumpDirection?) {
        guard lastReportedDirection != direction else { return }
        lastReportedDirection = direction
        onCurrentVerseVisibilityChange(direction)
    }
}

private struct VerseLyricsRow: View {
    let index: Int
    let verse: QuranVerse
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    isCurrent ? Color.white.opacity(0.95) : Color.white.opacity(0.65)
                )
                .frame(width: 30, alignment: .leading)

            Text(verse.textArabic)
                .font(isCurrent ? .title3 : .body)
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.82))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? Color.white.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }
}

private enum CurrentVerseJumpDirection: Equatable {
    case up
    case down

    var systemImage: String {
        switch self {
        case .up:
            return "arrow.up.circle.fill"
        case .down:
            return "arrow.down.circle.fill"
        }
    }
}

private struct VerseRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct VerseViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
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
