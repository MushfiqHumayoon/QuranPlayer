//
//  PlaybackStateStore.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Foundation

struct PlaybackSnapshot: Codable {
    let chapterID: Int
    let reciterID: Int
    let playbackTime: Double
}

final class PlaybackStateStore {
    static let shared = PlaybackStateStore()

    private let defaults: UserDefaults
    private let key = "quran_player_last_playback_snapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlaybackSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    func save(_ snapshot: PlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
