//
//  AudioPlayerManager.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentURL: URL?
    @Published private(set) var isReadyToPlay = false

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var playbackEndedObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false

    init() {
        configureAudioSession()
        registerAudioSessionObservers()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    func load(url: URL, autoplay: Bool, startAt: Double = 0) {
        teardownObservers()

        currentURL = url
        currentTime = 0
        duration = 0
        isReadyToPlay = false

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        observe(item: item, with: newPlayer)
        addTimeObserver(to: newPlayer)

        if startAt > 0 {
            let targetTime = CMTime(seconds: startAt, preferredTimescale: 600)
            newPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = startAt
        }

        if autoplay {
            newPlayer.play()
            isPlaying = true
        }
    }

    func play() {
        guard let player else { return }
        activateAudioSessionIfNeeded()
        player.play()
        isPlaying = true
    }

    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard let player else { return }

        let upperBound = duration > 0 ? duration : seconds
        let safeTime = min(max(0, seconds), upperBound)
        let target = CMTime(seconds: safeTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = safeTime
    }

    func seekBy(seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func stop() {
        player?.pause()
        isPlaying = false
        teardownObservers()
        player = nil
        currentURL = nil
        currentTime = 0
        duration = 0
        isReadyToPlay = false
    }

    private func observe(item: AVPlayerItem, with player: AVPlayer) {
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let itemDuration = item.duration.seconds
                if itemDuration.isFinite {
                    self.duration = itemDuration
                }

                self.isReadyToPlay = item.status == .readyToPlay
                self.isPlaying = player.rate > 0
            }
        }

        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }

                let itemDuration = player.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite {
                    self.duration = itemDuration
                }

                self.isPlaying = player.rate > 0
            }
        }
    }

    private func teardownObservers() {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            // Audio session setup can fail in previews; playback will still attempt to continue.
        }
    }

    private func activateAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
        } catch {
            // If activation fails, allow playback call to proceed anyway.
        }
    }

    private func registerAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleRouteChange(notification)
            }
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configureAudioSession()
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else {
            return
        }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            isPlaying = false
        case .ended:
            guard
                let optionRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            else {
                wasPlayingBeforeInterruption = false
                return
            }

            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume)
            if shouldResume && wasPlayingBeforeInterruption {
                play()
            } else {
                isPlaying = false
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else {
            return
        }

        // Keep state in sync when audio output route changes (e.g. headphones disconnect).
        if reason == .oldDeviceUnavailable, player?.rate == 0 {
            isPlaying = false
        }
    }
}
