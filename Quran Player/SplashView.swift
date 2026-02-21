//
//  SplashView.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import SwiftUI

struct SplashView: View {
    @State private var logoVisible = false
    @State private var backgroundFlowProgress = false

    var body: some View {
        ZStack {
            animatedTrendingBackground
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
        .onAppear {
            startBackgroundAnimation()
        }
    }

    private var animatedTrendingBackground: some View {
        let flowStart = UnitPoint(x: 0.5, y: backgroundFlowProgress ? -0.15 : 1.15)
        let flowEnd = UnitPoint(x: 0.5, y: backgroundFlowProgress ? 0.85 : 2.15)

        return ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.11, blue: 0.20),
                    Color(red: 0.06, green: 0.15, blue: 0.11),
                    Color(red: 0.09, green: 0.10, blue: 0.18),
                    Color(red: 0.12, green: 0.12, blue: 0.14)
                ],
                startPoint: flowStart,
                endPoint: flowEnd
            )
            .opacity(0.45)
            .blur(radius: 36)
        }
    }

    private func startBackgroundAnimation() {
        guard !backgroundFlowProgress else { return }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
            backgroundFlowProgress = true
        }
    }
}

#Preview {
    SplashView()
}
