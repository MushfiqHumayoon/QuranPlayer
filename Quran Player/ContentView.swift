//
//  ContentView.swift
//  Quran Player
//
//  Created by Mushfiq Humayoon on 20/02/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var playerViewModel: PlayerViewModel

    @MainActor
    init() {
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel())
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                HomeView(playerViewModel: playerViewModel)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}
