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
    func fetchAudioURL(chapterID: Int, reciterID: Int) async throws -> URL
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

    func fetchAudioURL(chapterID: Int, reciterID: Int) async throws -> URL {
        let response: ChapterRecitationResponse = try await fetch("chapter_recitations/\(reciterID)/\(chapterID)")
        guard let rawAudioURL = response.audioURL,
              let audioURL = normalizeAudioURL(from: rawAudioURL) else {
            throw QuranAPIError.missingAudioURL
        }

        return audioURL
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
}

private struct ChaptersResponse: Decodable {
    let chapters: [QuranChapter]
}

private struct RecitersResponse: Decodable {
    let recitations: [QuranReciter]
}

private struct ChapterRecitationResponse: Decodable {
    let audioURL: String?

    private enum CodingKeys: String, CodingKey {
        case audioFile
        case audioFiles
        case audioURL
        case audioUrl
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let direct = try container.decodeIfPresent(String.self, forKey: .audioURL), !direct.isEmpty {
            audioURL = direct
            return
        }

        if let direct = try container.decodeIfPresent(String.self, forKey: .audioUrl), !direct.isEmpty {
            audioURL = direct
            return
        }

        if let direct = try container.decodeIfPresent(String.self, forKey: .url), !direct.isEmpty {
            audioURL = direct
            return
        }

        if let file = try container.decodeIfPresent(ChapterAudioFile.self, forKey: .audioFile) {
            audioURL = file.audioURL
            return
        }

        if let files = try container.decodeIfPresent([ChapterAudioFile].self, forKey: .audioFiles),
           let firstURL = files.compactMap(\.audioURL).first {
            audioURL = firstURL
            return
        }

        audioURL = nil
    }
}

private struct ChapterAudioFile: Decodable {
    let audioURL: String?

    private enum CodingKeys: String, CodingKey {
        case audioURL
        case audioUrl
        case url
        case file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .audioURL), !value.isEmpty {
            audioURL = value
            return
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .audioUrl), !value.isEmpty {
            audioURL = value
            return
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .url), !value.isEmpty {
            audioURL = value
            return
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .file), !value.isEmpty {
            audioURL = value
            return
        }

        audioURL = nil
    }
}
