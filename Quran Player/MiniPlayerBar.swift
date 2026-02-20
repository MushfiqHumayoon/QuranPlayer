//
//  MiniPlayerBar.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.primary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerViewModel.currentChapter?.nameSimple ?? "Quran")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(playerViewModel.reciter?.reciterName ?? "Reciter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if playerViewModel.isLoadingAudio {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: playerViewModel.togglePlayPause) {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Button(action: playerViewModel.stop) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
    }
}
