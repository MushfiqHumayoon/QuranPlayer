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
    @Published private(set) var reciter: QuranReciter?
    @Published private(set) var isLoadingAudio = false
    @Published var errorMessage: String?

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isReadyToPlay = false
    @Published private(set) var isChapterCached = false
    @Published private(set) var isDownloadingCurrentChapter = false
    @Published private(set) var sleepTimerRemaining: TimeInterval?

    let player: AudioPlayerManager

    private let service: any QuranServiceProtocol
    private let cacheManager: AudioCacheManager
    private let playbackStore: PlaybackStateStore
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerTicker: AnyCancellable?
    private var lastPlaybackStoreSaveDate = Date.distantPast

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
        cancelSleepTimer()
        player.stop()
        currentChapter = nil
        chapters = []
        reciter = nil
        isLoadingAudio = false
        isChapterCached = false
        isDownloadingCurrentChapter = false
        errorMessage = nil
        clearNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        player.seek(to: seconds)
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
        isLoadingAudio = true
        errorMessage = nil
        isChapterCached = false
        updateNowPlayingInfo()
        persistPlaybackState(force: true)

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let source = try await self.resolvePlaybackSource(chapterID: chapterID, reciterID: reciterID)
                try Task.checkCancellation()

                await MainActor.run {
                    self.player.load(url: source.playbackURL, autoplay: autoplay, startAt: startTime)
                    self.isLoadingAudio = false
                    self.isChapterCached = source.isCached
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
            return PlaybackSource(playbackURL: localURL, isCached: true)
        }

        let remoteURL = try await resolveRemoteURL(chapterID: chapterID, reciterID: reciterID)
        return PlaybackSource(playbackURL: remoteURL, isCached: false)
    }

    private func resolveRemoteURL(chapterID: Int, reciterID: Int) async throws -> URL {
        if let cachedRemoteURL = await cacheManager.cachedRemoteURL(chapterID: chapterID, reciterID: reciterID) {
            return cachedRemoteURL
        }

        let remoteURL = try await service.fetchAudioURL(chapterID: chapterID, reciterID: reciterID)
        await cacheManager.storeRemoteURL(remoteURL, chapterID: chapterID, reciterID: reciterID)
        return remoteURL
    }
}

private struct PlaybackSource {
    let playbackURL: URL
    let isCached: Bool
}
