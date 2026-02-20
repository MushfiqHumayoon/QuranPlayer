//
//  QuranModels.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Foundation

struct QuranChapter: Identifiable, Codable, Hashable {
    let id: Int
    let nameSimple: String
    let nameArabic: String
    let versesCount: Int
    let revelationPlace: String
    let translatedName: ChapterTranslation

    struct ChapterTranslation: Codable, Hashable {
        let name: String
    }
}

struct QuranReciter: Identifiable, Codable, Hashable {
    let id: Int
    let reciterName: String
    let style: String?

    var displayName: String {
        guard let style, !style.isEmpty else {
            return reciterName
        }

        return "\(reciterName) (\(style))"
    }
}

enum QuranAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingAudioURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Unexpected response from Quran.com."
        case .missingAudioURL:
            return "No audio file was returned for this chapter."
        }
    }
}
