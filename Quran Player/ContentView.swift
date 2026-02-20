//
//  ContentView.swift
//  Quran Player
//
//  Created by Mushfiq Humayoon on 20/02/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var playerViewModel: PlayerViewModel
    @State private var isShowingSplash = true

    @MainActor
    init() {
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel())
    }

    var body: some View {
        ZStack {
            if isShowingSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                HomeView(playerViewModel: playerViewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: isShowingSplash)
        .task {
            guard isShowingSplash else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.55)) {
                isShowingSplash = false
            }
        }
    }
}
