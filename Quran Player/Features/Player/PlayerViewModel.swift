//
//  PlayerViewModel.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Combine
import Foundation
import MediaPlayer

enum SleepTimerPreset: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) min"
    }

    var duration: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var currentChapter: QuranChapter?
    @Published private(set) var chapters: [QuranChapter] = []
    @Published private(set) var verses: [QuranVerse] = []
    @Published private(set) var reciter: QuranReciter?
    @Published private(set) var isLoadingAudio = false
    @Published var errorMessage: String?

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isReadyToPlay = false
    @Published private(set) var isChapterCached = false
    @Published private(set) var isDownloadingCurrentChapter = false
    @Published private(set) var isLoadingVerses = false
    @Published private(set) var isLoadingTranslations = false
    @Published private(set) var verseStartTimes: [Double] = []
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    @Published private(set) var availableTranslations: [QuranTranslation] = [QuranTranslation.fallbackEnglish]
    @Published private(set) var selectedTranslationID: Int = QuranTranslation.fallbackEnglish.id

    let player: AudioPlayerManager

    private let service: any QuranServiceProtocol
    private let cacheManager: AudioCacheManager
    private let playbackStore: PlaybackStateStore
    private var loadTask: Task<Void, Never>?
    private var versesLoadTask: Task<Void, Never>?
    private var verseTimingsLoadTask: Task<Void, Never>?
    private var verseTimingLookup: [String: Double] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerTicker: AnyCancellable?
    private var lastPlaybackStoreSaveDate = Date.distantPast
    private var translationsLoadTask: Task<Void, Never>?

    init(
        service: (any QuranServiceProtocol)? = nil,
        player: AudioPlayerManager? = nil,
        cacheManager: AudioCacheManager? = nil,
        playbackStore: PlaybackStateStore? = nil
    ) {
        self.service = service ?? QuranAPIClient()
        self.player = player ?? AudioPlayerManager()
        self.cacheManager = cacheManager ?? .shared
        self.playbackStore = playbackStore ?? .shared
        bindPlayerState()
        configureRemoteCommands()
        loadAvailableTranslations()
    }

    var isSessionActive: Bool {
        currentChapter != nil && reciter != nil && (isLoadingAudio || player.currentURL != nil)
    }

    var hasActiveSleepTimer: Bool {
        sleepTimerRemaining != nil
    }

    var sleepTimerDisplayText: String? {
        guard let sleepTimerRemaining else { return nil }
        let remaining = max(0, Int(sleepTimerRemaining))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var canGoToPreviousChapter: Bool {
        guard let chapterIndex else { return false }
        return chapterIndex > 0
    }

    var canGoToNextChapter: Bool {
        guard let chapterIndex else { return false }
        return chapterIndex < chapters.count - 1
    }

    var currentVerseIndex: Int? {
        guard !verses.isEmpty else { return nil }

        if verseStartTimes.count == verses.count, !verseStartTimes.isEmpty {
            return verseIndex(for: currentTime, in: verseStartTimes)
        }

        return weightedFallbackVerseIndex()
    }

    var selectedTranslation: QuranTranslation? {
        availableTranslations.first(where: { $0.id == selectedTranslationID })
    }

    func startPlayback(chapter: QuranChapter, chapters: [QuranChapter], reciter: QuranReciter) {
        self.chapters = chapters
        self.reciter = reciter
        load(chapter: chapter, autoplay: true, startTime: 0)
    }

    func updateReciter(_ newReciter: QuranReciter) {
        let previousReciterID = reciter?.id
        guard previousReciterID != newReciter.id else { return }

        reciter = newReciter
        updateNowPlayingInfo()
        persistPlaybackState(force: true)

        guard let currentChapter, isSessionActive else { return }
        let shouldAutoplay = isPlaying || isLoadingAudio
        load(chapter: currentChapter, autoplay: shouldAutoplay, startTime: currentTime)
    }

    func selectTranslation(id translationID: Int) {
        guard availableTranslations.contains(where: { $0.id == translationID }) else { return }
        guard selectedTranslationID != translationID else { return }

        selectedTranslationID = translationID

        guard currentChapter != nil else { return }
        refreshCurrentChapterVerses()
    }

    func reloadTranslations() {
        loadAvailableTranslations()
    }

    func restoreSessionIfPossible(chapters: [QuranChapter], reciters: [QuranReciter]) {
        guard currentChapter == nil else { return }
        guard let snapshot = playbackStore.load() else { return }
        guard let restoredChapter = chapters.first(where: { $0.id == snapshot.chapterID }) else { return }
        guard let restoredReciter = reciters.first(where: { $0.id == snapshot.reciterID }) else { return }

        self.chapters = chapters
        self.reciter = restoredReciter
        load(chapter: restoredChapter, autoplay: false, startTime: snapshot.playbackTime)
    }

    func play() {
        player.play()
        persistPlaybackState(force: true)
    }

    func pause() {
        player.pause()
        persistPlaybackState(force: true)
    }

    func togglePlayPause() {
        player.togglePlayPause()
        persistPlaybackState(force: true)
    }

    func stop() {
        persistPlaybackState(force: true)
        loadTask?.cancel()
        loadTask = nil
        versesLoadTask?.cancel()
        versesLoadTask = nil
        verseTimingsLoadTask?.cancel()
        verseTimingsLoadTask = nil
        cancelSleepTimer()
        player.stop()
        currentChapter = nil
        chapters = []
        verses = []
        verseStartTimes = []
        verseTimingLookup = [:]
        reciter = nil
        isLoadingAudio = false
        isLoadingVerses = false
        isChapterCached = false
        isDownloadingCurrentChapter = false
        errorMessage = nil
        clearNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let upperBound = duration > 0 ? duration : seconds
        let safeTime = min(max(0, seconds), upperBound)
        currentTime = safeTime
        player.seek(to: safeTime)
        updateNowPlayingInfo()
        persistPlaybackState(force: true)
    }

    func seek(toVerseIndex index: Int) {
        guard verses.indices.contains(index) else { return }

        let targetTime: Double
        if verseStartTimes.count == verses.count, !verseStartTimes.isEmpty {
            targetTime = verseStartTimes[index]
        } else if duration > 0 {
            targetTime = weightedFallbackTime(forVerseIndex: index)
        } else {
            return
        }

        seek(to: targetTime)
    }

    func skipForward() {
        player.seekBy(seconds: 15)
    }

    func skipBackward() {
        player.seekBy(seconds: -15)
    }

    func playPreviousChapter() {
        guard canGoToPreviousChapter, let chapterIndex else { return }
        let previousChapter = chapters[chapterIndex - 1]
        load(chapter: previousChapter, autoplay: true, startTime: 0)
    }

    func playNextChapter() {
        guard canGoToNextChapter, let chapterIndex else { return }
        let nextChapter = chapters[chapterIndex + 1]
        load(chapter: nextChapter, autoplay: true, startTime: 0)
    }

    func setSleepTimer(_ preset: SleepTimerPreset) {
        cancelSleepTimer()

        let duration = preset.duration
        sleepTimerRemaining = duration

        sleepTimerTicker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard let remaining = self.sleepTimerRemaining else { return }
                self.sleepTimerRemaining = max(0, remaining - 1)
            }

        sleepTimerTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                guard self.sleepTimerRemaining != nil else { return }
                self.pause()
                self.cancelSleepTimer()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerTicker?.cancel()
        sleepTimerTicker = nil
        sleepTimerRemaining = nil
    }

    func downloadCurrentChapterForOffline() {
        guard let currentChapter, let reciter else { return }
        guard !isDownloadingCurrentChapter else { return }

        let chapterID = currentChapter.id
        let reciterID = reciter.id
        isDownloadingCurrentChapter = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let remoteURL = try await self.resolveRemoteURL(chapterID: chapterID, reciterID: reciterID)
                _ = try await self.cacheManager.downloadIfNeeded(
                    remoteURL: remoteURL,
                    chapterID: chapterID,
                    reciterID: reciterID
                )

                await MainActor.run {
                    self.isDownloadingCurrentChapter = false
                    self.refreshCacheStateIfCurrent(chapterID: chapterID, reciterID: reciterID)
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingCurrentChapter = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshCurrentChapterVerses() {
        guard let chapterID = currentChapter?.id else { return }
        let translationID = selectedTranslationID

        versesLoadTask?.cancel()
        isLoadingVerses = true

        versesLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedVerses = try await self.service.fetchVerses(
                    chapterID: chapterID,
                    translationID: translationID
                )
                await MainActor.run {
                    guard self.currentChapter?.id == chapterID else { return }
                    guard self.selectedTranslationID == translationID else { return }
                    self.verses = loadedVerses
                    self.rebuildVerseStartTimes()
                    self.isLoadingVerses = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.currentChapter?.id == chapterID else { return }
                    guard self.selectedTranslationID == translationID else { return }
                    self.isLoadingVerses = false
                }
            }
        }
    }

    private var chapterIndex: Int? {
        guard let currentChapter else { return nil }
        return chapters.firstIndex(where: { $0.id == currentChapter.id })
    }

    private func load(chapter: QuranChapter, autoplay: Bool, startTime: Double) {
        guard let reciterID = reciter?.id else {
            errorMessage = "No reciter selected."
            return
        }

        let chapterID = chapter.id
        currentChapter = chapter
        verses = []
        verseStartTimes = []
        verseTimingLookup = [:]
        isLoadingAudio = true
        isLoadingVerses = true
        errorMessage = nil
        isChapterCached = false
        updateNowPlayingInfo()
        persistPlaybackState(force: true)

        let translationID = selectedTranslationID
        versesLoadTask?.cancel()
        versesLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedVerses = try await self.service.fetchVerses(
                    chapterID: chapterID,
                    translationID: translationID
                )
                await MainActor.run {
                    guard self.currentChapter?.id == chapterID else { return }
                    guard self.selectedTranslationID == translationID else { return }
                    self.verses = loadedVerses
                    self.isLoadingVerses = false
                    self.rebuildVerseStartTimes()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.currentChapter?.id == chapterID else { return }
                    guard self.selectedTranslationID == translationID else { return }
                    self.verses = []
                    self.isLoadingVerses = false
                    self.verseStartTimes = []
                }
            }
        }

        verseTimingsLoadTask?.cancel()
        verseTimingsLoadTask = nil

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let source = try await self.resolvePlaybackSource(chapterID: chapterID, reciterID: reciterID)
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.currentChapter?.id == chapterID else { return }
                    self.player.load(url: source.playbackURL, autoplay: autoplay, startAt: startTime)
                    self.isLoadingAudio = false
                    self.isChapterCached = source.isCached
                    self.applyVerseTimings(source.verseTimings)

                    if source.isCached && source.verseTimings.isEmpty {
                        self.loadVerseTimingsInBackground(chapterID: chapterID, reciterID: reciterID)
                    }

                    self.updateNowPlayingInfo()
                    self.persistPlaybackState(force: true)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.isLoadingAudio = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadVerseTimingsInBackground(chapterID: Int, reciterID: Int) {
        verseTimingsLoadTask?.cancel()
        verseTimingsLoadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let chapterAudio = try await self.service.fetchChapterAudio(
                    chapterID: chapterID,
                    reciterID: reciterID
                )
                await self.cacheManager.storeRemoteURL(
                    chapterAudio.audioURL,
                    chapterID: chapterID,
                    reciterID: reciterID
                )

                await MainActor.run {
                    guard self.currentChapter?.id == chapterID, self.reciter?.id == reciterID else { return }
                    self.applyVerseTimings(chapterAudio.verseTimings)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func applyVerseTimings(_ verseTimings: [QuranVerseTiming]) {
        guard !verseTimings.isEmpty else { return }

        var lookup: [String: Double] = [:]
        for timing in verseTimings {
            guard timing.startTime.isFinite, timing.startTime >= 0 else { continue }
            if let existing = lookup[timing.verseKey] {
                lookup[timing.verseKey] = min(existing, timing.startTime)
            } else {
                lookup[timing.verseKey] = timing.startTime
            }
        }

        guard !lookup.isEmpty else { return }
        verseTimingLookup = lookup
        rebuildVerseStartTimes()
    }

    private func rebuildVerseStartTimes() {
        guard !verses.isEmpty else {
            verseStartTimes = []
            return
        }

        var starts: [Double?] = verses.map { verseTimingLookup[$0.verseKey] }
        let knownIndices = starts.indices.filter { starts[$0] != nil }

        guard knownIndices.count >= 2 else {
            verseStartTimes = []
            return
        }

        for knownPairIndex in 0..<(knownIndices.count - 1) {
            let leftIndex = knownIndices[knownPairIndex]
            let rightIndex = knownIndices[knownPairIndex + 1]
            guard rightIndex - leftIndex > 1 else { continue }
            guard let leftTime = starts[leftIndex], let rightTime = starts[rightIndex] else { continue }

            let segmentSpan = max(0, rightTime - leftTime)
            let intervalIndices = leftIndex..<rightIndex
            let intervalWeights = intervalIndices.map { Double(max(1, verses[$0].textArabic.count)) }
            let totalWeight = intervalWeights.reduce(0, +)
            guard totalWeight > 0 else { continue }

            var running = leftTime
            for intervalOffset in 0..<(intervalWeights.count - 1) {
                let step = segmentSpan * (intervalWeights[intervalOffset] / totalWeight)
                running += step
                starts[leftIndex + intervalOffset + 1] = running
            }
        }

        if let firstKnownIndex = knownIndices.first, firstKnownIndex > 0, let firstKnownTime = starts[firstKnownIndex] {
            let forwardStep: Double
            if knownIndices.count > 1,
               let secondTime = starts[knownIndices[1]],
               knownIndices[1] > firstKnownIndex {
                forwardStep = max(0.1, (secondTime - firstKnownTime) / Double(knownIndices[1] - firstKnownIndex))
            } else {
                forwardStep = estimatedVerseDurationStep()
            }

            var running = firstKnownTime
            for index in stride(from: firstKnownIndex - 1, through: 0, by: -1) {
                running = max(0, running - forwardStep)
                starts[index] = running
            }
        }

        if let lastKnownIndex = knownIndices.last, lastKnownIndex < starts.count - 1, let lastKnownTime = starts[lastKnownIndex] {
            let forwardStep: Double
            if knownIndices.count > 1,
               let previousTime = starts[knownIndices[knownIndices.count - 2]],
               lastKnownIndex > knownIndices[knownIndices.count - 2] {
                forwardStep = max(0.1, (lastKnownTime - previousTime) / Double(lastKnownIndex - knownIndices[knownIndices.count - 2]))
            } else {
                forwardStep = estimatedVerseDurationStep()
            }

            var running = lastKnownTime
            for index in (lastKnownIndex + 1)..<starts.count {
                running += forwardStep
                starts[index] = running
            }
        }

        var resolved = starts.map { $0 ?? 0 }
        if !resolved.isEmpty {
            resolved[0] = max(0, resolved[0])
        }
        for index in 1..<resolved.count {
            resolved[index] = max(resolved[index], resolved[index - 1])
        }

        verseStartTimes = resolved
    }

    private func estimatedVerseDurationStep() -> Double {
        guard duration > 0, !verses.isEmpty else { return 2.5 }
        return max(0.5, duration / Double(verses.count))
    }

    private func verseIndex(for playbackTime: Double, in verseStarts: [Double]) -> Int {
        guard !verseStarts.isEmpty else { return 0 }

        let safeTime = max(0, playbackTime)
        var low = 0
        var high = verseStarts.count

        while low < high {
            let mid = (low + high) / 2
            if verseStarts[mid] <= safeTime {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return min(max(0, low - 1), verseStarts.count - 1)
    }

    private func weightedFallbackVerseIndex() -> Int {
        guard duration > 0 else { return 0 }
        guard !verses.isEmpty else { return 0 }

        let safeTime = min(max(0, currentTime), duration)
        let weights = verses.map { Double(max(1, $0.textArabic.count)) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 0 }

        let target = (safeTime / duration) * totalWeight
        var cumulative: Double = 0

        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if target <= cumulative {
                return index
            }
        }

        return verses.count - 1
    }

    private func weightedFallbackTime(forVerseIndex index: Int) -> Double {
        guard duration > 0 else { return 0 }
        guard !verses.isEmpty else { return 0 }

        let clampedIndex = min(max(0, index), verses.count - 1)
        let weights = verses.map { Double(max(1, $0.textArabic.count)) }
        let totalWeight = weights.reduce(0, +)

        guard totalWeight > 0 else {
            let denominator = Double(max(1, verses.count - 1))
            return (Double(clampedIndex) / denominator) * duration
        }

        let precedingWeight = weights.prefix(clampedIndex).reduce(0, +)
        return min(duration, max(0, (precedingWeight / totalWeight) * duration))
    }

    private func bindPlayerState() {
        player.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.isPlaying = value
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        player.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.currentTime = value
                self?.updateNowPlayingInfo()
                self?.persistPlaybackState()
            }
            .store(in: &cancellables)

        player.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.duration = value
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        player.$isReadyToPlay
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.isReadyToPlay = value
            }
            .store(in: &cancellables)

        player.$playbackCompletionCount
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.canGoToNextChapter else {
                    self.persistPlaybackState(force: true)
                    return
                }
                self.playNextChapter()
            }
            .store(in: &cancellables)
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        registerRemoteCommand(commandCenter.playCommand) { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        registerRemoteCommand(commandCenter.pauseCommand) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        registerRemoteCommand(commandCenter.togglePlayPauseCommand) { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        registerRemoteCommand(commandCenter.nextTrackCommand) { [weak self] _ in
            Task { @MainActor in
                self?.playNextChapter()
            }
            return .success
        }

        registerRemoteCommand(commandCenter.previousTrackCommand) { [weak self] _ in
            Task { @MainActor in
                self?.playPreviousChapter()
            }
            return .success
        }

        registerRemoteCommand(commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.seek(to: seekEvent.positionTime)
            }
            return .success
        }

        updateRemoteCommandAvailability()
    }

    private func registerRemoteCommand(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        remoteCommandTargets.append((command, target))
    }

    private func updateNowPlayingInfo() {
        guard let currentChapter, let reciter else {
            clearNowPlayingInfo()
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        info[MPMediaItemPropertyTitle] = currentChapter.nameSimple
        info[MPMediaItemPropertyArtist] = reciter.reciterName
        info[MPMediaItemPropertyAlbumTitle] = "Quran"
        info[MPMediaItemPropertyComposer] = currentChapter.nameArabic
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateRemoteCommandAvailability()
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let isPlaybackActive = isSessionActive

        commandCenter.playCommand.isEnabled = isPlaybackActive
        commandCenter.pauseCommand.isEnabled = isPlaybackActive
        commandCenter.togglePlayPauseCommand.isEnabled = isPlaybackActive
        commandCenter.changePlaybackPositionCommand.isEnabled = isPlaybackActive && duration > 0
        commandCenter.nextTrackCommand.isEnabled = canGoToNextChapter
        commandCenter.previousTrackCommand.isEnabled = canGoToPreviousChapter
    }

    private func persistPlaybackState(force: Bool = false) {
        guard let currentChapter, let reciter else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastPlaybackStoreSaveDate) < 1 {
            return
        }
        lastPlaybackStoreSaveDate = now

        playbackStore.save(
            PlaybackSnapshot(
                chapterID: currentChapter.id,
                reciterID: reciter.id,
                playbackTime: currentTime
            )
        )
    }

    private func refreshCacheStateIfCurrent(chapterID: Int, reciterID: Int) {
        guard currentChapter?.id == chapterID, reciter?.id == reciterID else { return }

        Task { [weak self] in
            guard let self else { return }
            let cached = await self.cacheManager.isCached(chapterID: chapterID, reciterID: reciterID)
            await MainActor.run {
                guard self.currentChapter?.id == chapterID, self.reciter?.id == reciterID else { return }
                self.isChapterCached = cached
            }
        }
    }

    private func resolvePlaybackSource(chapterID: Int, reciterID: Int) async throws -> PlaybackSource {
        if let localURL = await cacheManager.cachedFileURL(chapterID: chapterID, reciterID: reciterID) {
            return PlaybackSource(playbackURL: localURL, isCached: true, verseTimings: [])
        }

        let chapterAudio = try await service.fetchChapterAudio(chapterID: chapterID, reciterID: reciterID)
        await cacheManager.storeRemoteURL(chapterAudio.audioURL, chapterID: chapterID, reciterID: reciterID)
        return PlaybackSource(
            playbackURL: chapterAudio.audioURL,
            isCached: false,
            verseTimings: chapterAudio.verseTimings
        )
    }

    private func resolveRemoteURL(chapterID: Int, reciterID: Int) async throws -> URL {
        if let cachedRemoteURL = await cacheManager.cachedRemoteURL(chapterID: chapterID, reciterID: reciterID) {
            return cachedRemoteURL
        }

        let chapterAudio = try await service.fetchChapterAudio(chapterID: chapterID, reciterID: reciterID)
        await cacheManager.storeRemoteURL(chapterAudio.audioURL, chapterID: chapterID, reciterID: reciterID)
        return chapterAudio.audioURL
    }

    private func loadAvailableTranslations() {
        translationsLoadTask?.cancel()
        isLoadingTranslations = true

        translationsLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedTranslations = try await self.service.fetchTranslations()
                await MainActor.run {
                    if !loadedTranslations.isEmpty {
                        self.availableTranslations = loadedTranslations
                    }

                    let previousTranslationID = self.selectedTranslationID
                    if !self.availableTranslations.contains(where: { $0.id == previousTranslationID }) {
                        self.selectedTranslationID = self.availableTranslations.first?.id ?? QuranTranslation.fallbackEnglish.id
                    }

                    self.isLoadingTranslations = false

                    if self.currentChapter != nil, previousTranslationID != self.selectedTranslationID {
                        self.refreshCurrentChapterVerses()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingTranslations = false
                }
            }
        }
    }
}

private struct PlaybackSource {
    let playbackURL: URL
    let isCached: Bool
    let verseTimings: [QuranVerseTiming]
}
