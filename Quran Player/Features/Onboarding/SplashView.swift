//
//  SplashView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoVisible = false

    var body: some View {
        ZStack {
            AnimatedBackground(colorScheme: colorScheme)
                .ignoresSafeArea()

            Image("QuranRounded")
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.26), radius: 24, y: 12)
                .scaleEffect(logoVisible ? 1 : 0.92)
                .opacity(logoVisible ? 1 : 0.5)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8)) {
                        logoVisible = true
                    }
                }
        }
    }
}

#Preview {
    SplashView()
}
