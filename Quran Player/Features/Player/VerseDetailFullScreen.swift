//
//  VerseDetailFullScreen.swift
//  Quran Player
//
//  Created by Codex on 22/02/26.
//

import SwiftUI

struct VerseDetailFullScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: PlayerViewModel
    @State private var hasRequestedTranslationRefresh = false
    @State private var isTranslationSearchPresented = false
    @State private var translationSearchText = ""

    private var detailContext: VerseDetailContext? {
        guard let chapter = viewModel.currentChapter,
              let verseIndex = viewModel.currentVerseIndex,
              viewModel.verses.indices.contains(verseIndex) else {
            return nil
        }

        return VerseDetailContext(
            chapterName: chapter.nameSimple,
            chapterArabicName: chapter.nameArabic,
            verseIndex: verseIndex,
            verse: viewModel.verses[verseIndex],
            reciterName: viewModel.reciter?.reciterName
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                    Color(red: 0.08, green: 0.11, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if let detailContext {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 8) {
                            Text("Ayah \(detailContext.verseIndex + 1)")
                            Text(detailContext.verse.verseKey)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))

                        VStack(spacing: 14) {
                            Text(detailContext.verse.textArabic)
                                .font(.system(size: 38, weight: .medium, design: .serif))
                                .lineSpacing(16)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text(viewModel.selectedTranslation?.displayName ?? "Translation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))

                            if let translation = detailContext.verse.textTranslation, !translation.isEmpty {
                                Text(translation)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("Translation unavailable for this verse.")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.58))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )

                        if let reciterName = detailContext.reciterName, !reciterName.isEmpty {
                            Text("Reciter: \(reciterName)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.66))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView("Loading verse")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
                        .padding(.top, 80)
                    }
            }

            HStack(spacing: 10) {
                translationChooserButton
                closeButton
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .onAppear {
            requestTranslationRefreshIfNeeded()
        }
        .onChange(of: viewModel.verses) { _, _ in
            requestTranslationRefreshIfNeeded()
        }
        .sheet(isPresented: $isTranslationSearchPresented) {
            translationSearchSheet
        }
    }

    @ViewBuilder
    private var translationChooserButton: some View {
        if viewModel.isLoadingTranslations && viewModel.availableTranslations.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.16))
                .clipShape(Circle())
        } else {
            Button {
                if viewModel.availableTranslations.isEmpty {
                    viewModel.reloadTranslations()
                }
                isTranslationSearchPresented = true
            } label: {
                Image(systemName: viewModel.availableTranslations.isEmpty ? "globe.badge.chevron.backward" : "globe")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.16))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close verse details")
    }

    private var translationSearchSheet: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingTranslations && viewModel.availableTranslations.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading translation languages")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.availableTranslations.isEmpty {
                    Text("Translation languages unavailable right now.")
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        viewModel.reloadTranslations()
                    }
                } else if filteredTranslations.isEmpty {
                    Text("No matching translations.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTranslations) { translation in
                        Button {
                            viewModel.selectTranslation(id: translation.id)
                            isTranslationSearchPresented = false
                        } label: {
                            HStack {
                                Text(translation.displayName)
                                Spacer()
                                if translation.id == viewModel.selectedTranslationID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Translations")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $translationSearchText, prompt: "Search translations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isTranslationSearchPresented = false
                    }
                }
            }
        }
        .onDisappear {
            translationSearchText = ""
        }
    }

    private var filteredTranslations: [QuranTranslation] {
        let query = translationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.availableTranslations }

        return viewModel.availableTranslations.filter { translation in
            translation.displayName.localizedCaseInsensitiveContains(query)
                || translation.name.localizedCaseInsensitiveContains(query)
                || translation.languageName.localizedCaseInsensitiveContains(query)
                || (translation.authorName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func requestTranslationRefreshIfNeeded() {
        guard !hasRequestedTranslationRefresh else { return }
        guard viewModel.currentChapter != nil else { return }

        if viewModel.verses.isEmpty {
            hasRequestedTranslationRefresh = true
            viewModel.refreshCurrentChapterVerses()
            return
        }

        let hasAnyTranslation = viewModel.verses.contains {
            guard let translation = $0.textTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !translation.isEmpty
        }

        guard !hasAnyTranslation else { return }

        hasRequestedTranslationRefresh = true
        viewModel.refreshCurrentChapterVerses()
    }
}

private struct VerseDetailContext {
    let chapterName: String
    let chapterArabicName: String
    let verseIndex: Int
    let verse: QuranVerse
    let reciterName: String?
}
