//
//  AudioCacheManager.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Foundation

actor AudioCacheManager {
    static let shared = AudioCacheManager()

    private struct CacheEntry: Codable {
        let chapterID: Int
        let reciterID: Int
        let remoteURL: String
        let filename: String
        let createdAt: Date
    }

    private var entries: [String: CacheEntry]
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let indexFileURL: URL

    init() {
        let fileManager = FileManager.default
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.cacheDirectory = appSupport.appendingPathComponent("QuranAudioCache", isDirectory: true)
        self.indexFileURL = cacheDirectory.appendingPathComponent("index.json")
        self.entries = [:]

        Self.createCacheDirectoryIfNeeded(fileManager: fileManager, cacheDirectory: cacheDirectory)
        self.entries = Self.loadIndex(from: indexFileURL)
    }

    func isCached(chapterID: Int, reciterID: Int) -> Bool {
        cachedFileURL(chapterID: chapterID, reciterID: reciterID) != nil
    }

    func cachedFileURL(chapterID: Int, reciterID: Int) -> URL? {
        let key = entryKey(chapterID: chapterID, reciterID: reciterID)
        guard let entry = entries[key] else { return nil }

        let localURL = cacheDirectory.appendingPathComponent(entry.filename)
        guard fileManager.fileExists(atPath: localURL.path) else {
            entries.removeValue(forKey: key)
            persistIndex()
            return nil
        }

        return localURL
    }

    func cachedRemoteURL(chapterID: Int, reciterID: Int) -> URL? {
        let key = entryKey(chapterID: chapterID, reciterID: reciterID)
        guard let remoteURLString = entries[key]?.remoteURL else { return nil }
        return URL(string: remoteURLString)
    }

    func storeRemoteURL(_ remoteURL: URL, chapterID: Int, reciterID: Int) {
        let key = entryKey(chapterID: chapterID, reciterID: reciterID)
        let existingFilename = entries[key]?.filename ?? defaultFilename(remoteURL: remoteURL, chapterID: chapterID, reciterID: reciterID)

        entries[key] = CacheEntry(
            chapterID: chapterID,
            reciterID: reciterID,
            remoteURL: remoteURL.absoluteString,
            filename: existingFilename,
            createdAt: Date()
        )
        persistIndex()
    }

    func downloadIfNeeded(remoteURL: URL, chapterID: Int, reciterID: Int) async throws -> URL {
        if let local = cachedFileURL(chapterID: chapterID, reciterID: reciterID) {
            return local
        }

        let key = entryKey(chapterID: chapterID, reciterID: reciterID)
        let filename = entries[key]?.filename ?? defaultFilename(remoteURL: remoteURL, chapterID: chapterID, reciterID: reciterID)
        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        entries[key] = CacheEntry(
            chapterID: chapterID,
            reciterID: reciterID,
            remoteURL: remoteURL.absoluteString,
            filename: filename,
            createdAt: Date()
        )
        persistIndex()

        return destinationURL
    }

    private func entryKey(chapterID: Int, reciterID: Int) -> String {
        "\(reciterID)-\(chapterID)"
    }

    private func defaultFilename(remoteURL: URL, chapterID: Int, reciterID: Int) -> String {
        let fileExtension = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        return "\(reciterID)_\(chapterID).\(fileExtension)"
    }

    private static func createCacheDirectoryIfNeeded(fileManager: FileManager, cacheDirectory: URL) {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            return
        }

        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    private static func loadIndex(from indexFileURL: URL) -> [String: CacheEntry] {
        guard
            let data = try? Data(contentsOf: indexFileURL),
            let loadedEntries = try? JSONDecoder().decode([String: CacheEntry].self, from: data)
        else {
            return [:]
        }

        return loadedEntries
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexFileURL, options: [.atomic])
    }
}
