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

struct QuranTranslation: Identifiable, Hashable {
    let id: Int
    let name: String
    let languageName: String
    let authorName: String?

    var displayName: String {
        let language = languageName.trimmingCharacters(in: .whitespacesAndNewlines)
        let translationName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if language.isEmpty {
            return translationName
        }
        if translationName.isEmpty {
            return language
        }

        return "\(language) - \(translationName)"
    }

    static let fallbackEnglish = QuranTranslation(
        id: 20,
        name: "Sahih International",
        languageName: "English",
        authorName: nil
    )
}

struct QuranVerse: Identifiable, Hashable {
    let id: Int
    let verseKey: String
    let textArabic: String
    let textTranslation: String?
}

struct QuranVerseTiming: Hashable {
    let verseKey: String
    let startTime: Double
}

struct QuranChapterAudio: Hashable {
    let audioURL: URL
    let verseTimings: [QuranVerseTiming]
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
