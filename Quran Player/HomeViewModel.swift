//
//  HomeViewModel.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var chapters: [QuranChapter] = []
    @Published private(set) var reciters: [QuranReciter] = []
    @Published var selectedReciterID: Int?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let service: any QuranServiceProtocol

    init(service: (any QuranServiceProtocol)? = nil) {
        self.service = service ?? QuranAPIClient()
    }

    var selectedReciter: QuranReciter? {
        reciters.first(where: { $0.id == selectedReciterID })
    }

    func loadIfNeeded() async {
        guard chapters.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let chaptersTask = service.fetchChapters()
            async let recitersTask = service.fetchReciters()

            let (loadedChapters, loadedReciters) = try await (chaptersTask, recitersTask)
            chapters = loadedChapters
            reciters = loadedReciters

            if selectedReciterID == nil {
                selectedReciterID = preferredReciterID(from: loadedReciters)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func preferredReciterID(from reciters: [QuranReciter]) -> Int? {
        if let mishary = reciters.first(where: { $0.id == 7 }) {
            return mishary.id
        }

        return reciters.first?.id
    }
}
