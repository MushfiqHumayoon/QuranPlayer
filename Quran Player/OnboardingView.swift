//
//  OnboardingView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.14),
                    Color(red: 0.12, green: 0.30, blue: 0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)

                Text("Quran Player")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("A minimal Quran-only listening app inspired by native music players.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Button(action: onContinue) {
                    Text("Start Listening")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        }
    }
}
