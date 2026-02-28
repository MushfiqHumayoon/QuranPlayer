//
//  PlayerView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import AdaptyUI
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: PlayerViewModel
    @EnvironmentObject private var paywallManager: PaywallManager

    @State private var scrubTime: Double = 0
    @State private var isEditingSlider = false
    @State private var isOptionsSheetPresented = false
    @State private var currentVerseOffscreenDirection: CurrentVerseJumpDirection?
    @State private var jumpToCurrentVerseRequestID = 0
    @State private var scrollToTopRequestID = 0
    @State private var isVerseDetailPresented = false
    @State private var shouldPresentPaywallAfterSheetDismiss = false

    var body: some View {
        Group {
            if let chapter = viewModel.currentChapter {
                playerBody(chapter: chapter)
            } else {
                ZStack {
                    AnimatedBackground(colorScheme: colorScheme).ignoresSafeArea()
                    ProgressView()
                        .tint(AppTheme.primaryText(colorScheme))
                }
            }
        }
        .onChange(of: viewModel.currentTime) { _, newValue in
            if !isEditingSlider {
                scrubTime = newValue
            }
        }
        .sheet(isPresented: $isOptionsSheetPresented) {
            PlayerOptionsSheet(
                onRequestSubscriptionAccess: requestSubscriptionAccessSafely
            )
                .environmentObject(viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isVerseDetailPresented) {
            VerseDetailFullScreen()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .paywall(
            isPresented: $paywallManager.isPresented,
            paywallConfiguration: paywallManager.paywallConfiguration,
            didFinishPurchase: { _, result in
                paywallManager.handleDidFinishPurchase(result)
            },
            didFailPurchase: { _, error in
                paywallManager.handleFailedPurchase(error)
            },
            didFinishRestore: { profile in
                paywallManager.handleDidFinishRestore(profile)
            },
            didFailRestore: { error in
                paywallManager.handleFailedRestore(error)
            },
            didFailRendering: { error in
                paywallManager.handleFailedRendering(error)
            }
        )
        .alert("Playback Error", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onChange(of: isOptionsSheetPresented) { _, _ in
            presentQueuedPaywallIfNeeded()
        }
        .onChange(of: isVerseDetailPresented) { _, _ in
            presentQueuedPaywallIfNeeded()
        }
    }

    @ViewBuilder
    private func playerBody(chapter: QuranChapter) -> some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 760

            ZStack {
                AnimatedBackground(colorScheme: colorScheme)
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
                        .tint(AppTheme.primaryText(colorScheme))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomPlaybackBar(chapter: chapter)
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
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(AppTheme.buttonBackground(colorScheme))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(chapter.nameSimple)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))

                Text(chapter.nameArabic)
                    .font(.title3)
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
            }

            Spacer()

            Button {
                isOptionsSheetPresented = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(AppTheme.buttonBackground(colorScheme))
                    .clipShape(Circle())
            }
        }
    }

    private func artwork(maxWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.buttonBackground(colorScheme),
                        AppTheme.cardBackground(colorScheme)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
            }
            .frame(maxWidth: maxWidth)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 14)
    }

    private func metadata(chapter: QuranChapter) -> some View {
        VStack(spacing: 8) {
            if viewModel.isDownloadingCurrentChapter {
                Label("Downloading for offline playback", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText(colorScheme))
            } else if viewModel.isChapterCached {
                Label("Available offline", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText(colorScheme))
            }

            if let sleepTimerDisplayText = viewModel.sleepTimerDisplayText {
                Text("Sleep in \(sleepTimerDisplayText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText(colorScheme))
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
            Text(viewModel.reciter?.reciterName ?? "Quran")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText(colorScheme))
                .lineLimit(1)
            
            Spacer()

            if let verseIndex = viewModel.currentVerseIndex, !viewModel.verses.isEmpty {
                HStack(spacing: 8) {
                    Text("Ayah \(verseIndex + 1)/\(viewModel.verses.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText(colorScheme))

                    if let currentVerseOffscreenDirection {
                        Button {
                            jumpToCurrentVerseRequestID += 1
                        } label: {
                            Image(systemName: currentVerseOffscreenDirection.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText(colorScheme))
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
                .fill(AppTheme.cardBackground(colorScheme))
                .overlay {
                    if viewModel.isLoadingVerses {
                        ProgressView("Loading verses")
                            .font(.caption)
                            .tint(AppTheme.primaryText(colorScheme))
                    } else {
                        Text("Verses unavailable for this chapter.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText(colorScheme))
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
                    if verseIndex == viewModel.currentVerseIndex {
                        isVerseDetailPresented = true
                        return
                    }

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
            .tint(AppTheme.primaryText(colorScheme))

            HStack {
                Text(formatTime(viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText(colorScheme))
        }
    }

    private func bottomPlaybackBar(chapter: QuranChapter) -> some View {
        VStack(spacing: 8) {
            progressSection
            controls(chapter: chapter)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
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
            .foregroundStyle(AppTheme.primaryText(colorScheme))
            .buttonStyle(.plain)
            .symbolRenderingMode(.hierarchical)
            .opacity(viewModel.isLoadingAudio ? 0.6 : 1)
            .disabled(viewModel.isLoadingAudio)

            Text("Chapter \(chapter.id) - \(chapter.translatedName.name) | \(chapter.versesCount) verses")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(colorScheme))
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

    private func requestSubscriptionAccessSafely() {
        if isOptionsSheetPresented || isVerseDetailPresented {
            shouldPresentPaywallAfterSheetDismiss = true
            isOptionsSheetPresented = false
            isVerseDetailPresented = false
            return
        }

        viewModel.requestSubscriptionAccess?()
    }

    private func presentQueuedPaywallIfNeeded() {
        guard shouldPresentPaywallAfterSheetDismiss else { return }
        guard !isOptionsSheetPresented, !isVerseDetailPresented else { return }
        shouldPresentPaywallAfterSheetDismiss = false
        viewModel.requestSubscriptionAccess?()
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
    @State private var hasHandledInitialScroll = false

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
                handleInitialScroll(proxy: proxy)
                updateCurrentVerseDirection()
            }
            .onChange(of: highlightedIndex) { _, _ in
                handleInitialScroll(proxy: proxy)
                updateCurrentVerseDirection()
            }
            .onChange(of: verses.count) { _, _ in
                handleInitialScroll(proxy: proxy)
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

    private func handleInitialScroll(proxy: ScrollViewProxy) {
        guard !hasHandledInitialScroll else { return }
        guard !verses.isEmpty else { return }

        guard let highlightedIndex, verses.indices.contains(highlightedIndex) else {
            handleScrollToTopRequest(proxy: proxy, animated: false)
            return
        }

        hasHandledInitialScroll = true

        // Defer to next run loop so row IDs are in the hierarchy before scrolling.
        DispatchQueue.main.async {
            scrollToHighlightedVerse(proxy: proxy, animated: false)
            reportCurrentVerseDirection(nil)
        }
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
    @Environment(\.colorScheme) private var colorScheme
    let index: Int
    let verse: QuranVerse
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    isCurrent ? AppTheme.primaryText(colorScheme) : AppTheme.tertiaryText(colorScheme)
                )
                .frame(width: 30, alignment: .leading)

            Text(verse.textArabic)
                .font(.title3)
                .foregroundStyle(isCurrent ? AppTheme.primaryText(colorScheme) : AppTheme.secondaryText(colorScheme))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? AppTheme.buttonBackground(colorScheme) : AppTheme.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? AppTheme.border(colorScheme) : Color.clear, lineWidth: 1)
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
    let onRequestSubscriptionAccess: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Offline") {
                    if !viewModel.isSubscribed {
                        Button {
                            onRequestSubscriptionAccess()
                        } label: {
                            Label("Subscribe to Play Offline", systemImage: "lock.fill")
                        }
                    } else {
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
                }

                Section("Sleep Timer") {
                    if !viewModel.isSubscribed {
                        Button {
                            onRequestSubscriptionAccess()
                        } label: {
                            Label("Subscribe to Enable Sleep Timer", systemImage: "lock.fill")
                        }
                    } else {
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
            }
            .navigationTitle("Player Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
