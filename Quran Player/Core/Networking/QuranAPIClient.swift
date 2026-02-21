//
//  QuranAPIClient.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Foundation

protocol QuranServiceProtocol {
    func fetchChapters() async throws -> [QuranChapter]
    func fetchReciters() async throws -> [QuranReciter]
    func fetchChapterAudio(chapterID: Int, reciterID: Int) async throws -> QuranChapterAudio
    func fetchAudioURL(chapterID: Int, reciterID: Int) async throws -> URL
    func fetchVerses(chapterID: Int) async throws -> [QuranVerse]
}

struct QuranAPIClient: QuranServiceProtocol {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.quran.com/api/v4/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchChapters() async throws -> [QuranChapter] {
        let response: ChaptersResponse = try await fetch("chapters?language=en")
        return response.chapters.sorted { $0.id < $1.id }
    }

    func fetchReciters() async throws -> [QuranReciter] {
        let response: RecitersResponse = try await fetch("resources/recitations?language=en")
        return response.recitations.sorted { $0.id < $1.id }
    }

    func fetchChapterAudio(chapterID: Int, reciterID: Int) async throws -> QuranChapterAudio {
        let response: ChapterRecitationResponse = try await fetch(
            "chapter_recitations/\(reciterID)/\(chapterID)?segments=true"
        )
        guard let rawAudioURL = response.audioURL,
              let audioURL = normalizeAudioURL(from: rawAudioURL) else {
            throw QuranAPIError.missingAudioURL
        }

        let verseTimings = normalizeVerseTimings(
            response.rawVerseTimings,
            chapterID: chapterID,
            durationHint: response.durationHint
        )

        return QuranChapterAudio(audioURL: audioURL, verseTimings: verseTimings)
    }

    func fetchAudioURL(chapterID: Int, reciterID: Int) async throws -> URL {
        try await fetchChapterAudio(chapterID: chapterID, reciterID: reciterID).audioURL
    }

    func fetchVerses(chapterID: Int) async throws -> [QuranVerse] {
        let response: ChapterVersesResponse = try await fetch(
            "verses/by_chapter/\(chapterID)?words=false&per_page=300&fields=text_uthmani,verse_key"
        )

        return response.verses.enumerated().compactMap { offset, verse in
            let textCandidates = [
                verse.textUthmani,
                verse.textUthmaniSimple,
                verse.textIndopak,
                verse.textImlaei,
                verse.text
            ]
            let text = textCandidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })

            guard let text else { return nil }

            let verseKey = verse.verseKey ?? "\(chapterID):\(offset + 1)"
            let fallbackID = Int(verseKey.split(separator: ":").last ?? "") ?? (offset + 1)
            return QuranVerse(
                id: verse.id ?? fallbackID,
                verseKey: verseKey,
                textArabic: text
            )
        }
    }

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw QuranAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw QuranAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(T.self, from: data)
        } catch is DecodingError {
            throw QuranAPIError.invalidResponse
        }
    }

    private func normalizeAudioURL(from rawValue: String) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }

        if rawValue.hasPrefix("/") {
            return URL(string: "https://audio.qurancdn.com\(rawValue)")
        }

        return URL(string: "https://\(rawValue)")
    }

    private func normalizeVerseTimings(
        _ rawTimings: [RawVerseTiming],
        chapterID: Int,
        durationHint: Double?
    ) -> [QuranVerseTiming] {
        guard !rawTimings.isEmpty else { return [] }

        let maxRawValue = rawTimings.map(\.startRaw).max() ?? 0
        let shouldTreatAsMilliseconds: Bool
        if maxRawValue >= 10_000 {
            shouldTreatAsMilliseconds = true
        } else if let durationHint, durationHint > 0, maxRawValue > durationHint * 1.5 {
            shouldTreatAsMilliseconds = true
        } else {
            shouldTreatAsMilliseconds = false
        }

        var earliestStartByVerseKey: [String: Double] = [:]
        for rawTiming in rawTimings {
            let startTime = shouldTreatAsMilliseconds ? rawTiming.startRaw / 1000 : rawTiming.startRaw
            guard startTime.isFinite, startTime >= 0 else { continue }

            let verseKey: String
            if let rawVerseKey = rawTiming.verseKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawVerseKey.isEmpty {
                verseKey = rawVerseKey
            } else if let verseNumber = rawTiming.verseNumber, verseNumber > 0 {
                verseKey = "\(chapterID):\(verseNumber)"
            } else {
                continue
            }

            if let existing = earliestStartByVerseKey[verseKey] {
                earliestStartByVerseKey[verseKey] = min(existing, startTime)
            } else {
                earliestStartByVerseKey[verseKey] = startTime
            }
        }

        return earliestStartByVerseKey
            .map { QuranVerseTiming(verseKey: $0.key, startTime: $0.value) }
            .sorted(by: { $0.startTime < $1.startTime })
    }
}

private struct ChaptersResponse: Decodable {
    let chapters: [QuranChapter]
}

private struct RecitersResponse: Decodable {
    let recitations: [QuranReciter]
}

private struct ChapterRecitationResponse: Decodable {
    let audioURL: String?
    let rawVerseTimings: [RawVerseTiming]
    let durationHint: Double?

    private enum CodingKeys: String, CodingKey {
        case audioFile
        case audioFiles
        case audioURL
        case audioUrl
        case url
        case verseTimings
        case timings
        case timestamps
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let directAudioURL: String?
        if let direct = try container.decodeIfPresent(String.self, forKey: .audioURL), !direct.isEmpty {
            directAudioURL = direct
        } else if let direct = try container.decodeIfPresent(String.self, forKey: .audioUrl), !direct.isEmpty {
            directAudioURL = direct
        } else if let direct = try container.decodeIfPresent(String.self, forKey: .url), !direct.isEmpty {
            directAudioURL = direct
        } else {
            directAudioURL = nil
        }

        let topLevelTimings = Self.decodeRawTimings(from: container)
        let topLevelDuration = container.decodeLossyDouble(forKey: .duration)

        let audioFile = try? container.decode(ChapterAudioFile.self, forKey: .audioFile)
        let audioFiles = try? container.decode([ChapterAudioFile].self, forKey: .audioFiles)

        audioURL = directAudioURL ?? audioFile?.audioURL ?? audioFiles?.compactMap(\.audioURL).first

        if !topLevelTimings.isEmpty {
            rawVerseTimings = topLevelTimings
        } else if let audioFile, !audioFile.rawVerseTimings.isEmpty {
            rawVerseTimings = audioFile.rawVerseTimings
        } else if let firstWithTimings = audioFiles?.first(where: { !$0.rawVerseTimings.isEmpty }) {
            rawVerseTimings = firstWithTimings.rawVerseTimings
        } else {
            rawVerseTimings = []
        }

        durationHint = topLevelDuration
            ?? audioFile?.durationHint
            ?? audioFiles?.compactMap(\.durationHint).first
    }

    private static func decodeRawTimings(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [RawVerseTiming] {
        var rawTimings: [RawVerseTiming] = []

        for key in [CodingKeys.verseTimings, .timings, .timestamps] {
            if let payloads = try? container.decode([VerseTimingPayload].self, forKey: key) {
                rawTimings.append(contentsOf: payloads.compactMap(\.asRawTiming))
            }

            if let map = try? container.decode([String: Double].self, forKey: key) {
                rawTimings.append(
                    contentsOf: map.map { RawVerseTiming(verseKey: $0.key, verseNumber: nil, startRaw: $0.value) }
                )
            } else if let map = try? container.decode([String: Int].self, forKey: key) {
                rawTimings.append(
                    contentsOf: map.map {
                        RawVerseTiming(verseKey: $0.key, verseNumber: nil, startRaw: Double($0.value))
                    }
                )
            } else if let map = try? container.decode([String: String].self, forKey: key) {
                rawTimings.append(
                    contentsOf: map.compactMap { key, value in
                        guard let startRaw = Double(value) else { return nil }
                        return RawVerseTiming(verseKey: key, verseNumber: nil, startRaw: startRaw)
                    }
                )
            }
        }

        return rawTimings
    }
}

private struct ChapterVersesResponse: Decodable {
    let verses: [QuranVersePayload]
}

private struct QuranVersePayload: Decodable {
    let id: Int?
    let verseKey: String?
    let textUthmani: String?
    let textUthmaniSimple: String?
    let textIndopak: String?
    let textImlaei: String?
    let text: String?
}

private struct ChapterAudioFile: Decodable {
    let audioURL: String?
    let rawVerseTimings: [RawVerseTiming]
    let durationHint: Double?

    private enum CodingKeys: String, CodingKey {
        case audioURL
        case audioUrl
        case url
        case file
        case verseTimings
        case timings
        case timestamps
        case duration
        case durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let directAudioURL: String?
        if let value = try container.decodeIfPresent(String.self, forKey: .audioURL), !value.isEmpty {
            directAudioURL = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .audioUrl), !value.isEmpty {
            directAudioURL = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .url), !value.isEmpty {
            directAudioURL = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .file), !value.isEmpty {
            directAudioURL = value
        } else {
            directAudioURL = nil
        }

        audioURL = directAudioURL
        durationHint = container.decodeLossyDouble(forKey: .duration)
            ?? container.decodeLossyDouble(forKey: .durationSeconds)

        var decodedRawTimings: [RawVerseTiming] = []
        for key in [CodingKeys.verseTimings, .timings, .timestamps] {
            if let payloads = try? container.decode([VerseTimingPayload].self, forKey: key) {
                decodedRawTimings.append(contentsOf: payloads.compactMap(\.asRawTiming))
            }

            if let map = try? container.decode([String: Double].self, forKey: key) {
                decodedRawTimings.append(
                    contentsOf: map.map { RawVerseTiming(verseKey: $0.key, verseNumber: nil, startRaw: $0.value) }
                )
            } else if let map = try? container.decode([String: Int].self, forKey: key) {
                decodedRawTimings.append(
                    contentsOf: map.map {
                        RawVerseTiming(verseKey: $0.key, verseNumber: nil, startRaw: Double($0.value))
                    }
                )
            } else if let map = try? container.decode([String: String].self, forKey: key) {
                decodedRawTimings.append(
                    contentsOf: map.compactMap { key, value in
                        guard let startRaw = Double(value) else { return nil }
                        return RawVerseTiming(verseKey: key, verseNumber: nil, startRaw: startRaw)
                    }
                )
            }
        }

        rawVerseTimings = decodedRawTimings
    }
}

private struct RawVerseTiming: Hashable {
    let verseKey: String?
    let verseNumber: Int?
    let startRaw: Double
}

private struct VerseTimingPayload: Decodable {
    let verseKey: String?
    let verseNumber: Int?
    let startRaw: Double?

    private enum CodingKeys: String, CodingKey {
        case verseKey
        case ayahKey
        case verse
        case ayah
        case verseNumber
        case number
        case timestampFrom
        case timestampTo
        case timestamp
        case start
        case from
        case startTime
        case time
    }

    var asRawTiming: RawVerseTiming? {
        guard let startRaw, startRaw.isFinite, startRaw >= 0 else { return nil }
        return RawVerseTiming(verseKey: verseKey, verseNumber: verseNumber, startRaw: startRaw)
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let rawVerseKey = container.decodeLossyString(forKey: .verseKey)
                ?? container.decodeLossyString(forKey: .ayahKey)
            let verseNumber = container.decodeLossyInt(forKey: .verseNumber)
                ?? container.decodeLossyInt(forKey: .ayah)
                ?? container.decodeLossyInt(forKey: .verse)
                ?? container.decodeLossyInt(forKey: .number)

            let startRaw = container.decodeLossyDouble(forKey: .timestampFrom)
                ?? container.decodeLossyDouble(forKey: .start)
                ?? container.decodeLossyDouble(forKey: .from)
                ?? container.decodeLossyDouble(forKey: .startTime)
                ?? container.decodeLossyDouble(forKey: .timestamp)
                ?? container.decodeLossyDouble(forKey: .time)

            if let rawVerseKey = rawVerseKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawVerseKey.isEmpty {
                verseKey = rawVerseKey
            } else {
                verseKey = nil
            }
            self.verseNumber = verseNumber
            self.startRaw = startRaw
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            let firstString = (try? container.decode(String.self))
            let firstInt = firstString == nil ? (try? container.decode(Int.self)) : nil
            let firstDouble = (firstString == nil && firstInt == nil) ? (try? container.decode(Double.self)) : nil

            let secondInt = try? container.decode(Int.self)
            let secondDouble = secondInt == nil ? (try? container.decode(Double.self)) : nil
            let secondString = (secondInt == nil && secondDouble == nil) ? (try? container.decode(String.self)) : nil

            if let firstString, firstString.contains(":") {
                verseKey = firstString
                verseNumber = nil
            } else if let firstString, let number = Int(firstString) {
                verseKey = nil
                verseNumber = number
            } else if let firstInt {
                verseKey = nil
                verseNumber = firstInt
            } else if let firstDouble {
                verseKey = nil
                verseNumber = Int(firstDouble)
            } else {
                verseKey = nil
                verseNumber = nil
            }

            if let secondInt {
                startRaw = Double(secondInt)
            } else if let secondDouble {
                startRaw = secondDouble
            } else if let secondString, let parsed = Double(secondString) {
                startRaw = parsed
            } else {
                startRaw = nil
            }
            return
        }

        verseKey = nil
        verseNumber = nil
        startRaw = nil
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}
