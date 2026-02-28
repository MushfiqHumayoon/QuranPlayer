//
//  ContentView.swift
//  Quran Player
//
//  Created by Mushfiq Humayoon on 20/02/26.
//

import AdaptyUI
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playerViewModel: PlayerViewModel
    @StateObject private var paywallManager = PaywallManager()
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
                    .environmentObject(paywallManager)
                    .transition(.opacity)
            }
        }
        .paywall(
            isPresented: $paywallManager.isPresented,
            paywallConfiguration: paywallManager.paywallConfiguration,
            didFinishPurchase: { _, result in
                paywallManager.handleDidFinishPurchase(result)
            },
            didFailPurchase: { _, error in
                paywallManager.handleFailedPurchase(error)
            },
            didFinishRestore: { profile in
                paywallManager.handleDidFinishRestore(profile)
            },
            didFailRestore: { error in
                paywallManager.handleFailedRestore(error)
            },
            didFailRendering: { error in
                paywallManager.handleFailedRendering(error)
            }
        )
        .alert(item: $paywallManager.presentationError) { paywallError in
            Alert(
                title: Text("Paywall Error"),
                message: Text(paywallError.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .animation(.easeInOut(duration: 0.55), value: isShowingSplash)
        .onAppear {
            playerViewModel.requestSubscriptionAccess = { [paywallManager] in
                paywallManager.presentPaywall()
            }
            playerViewModel.setSubscriptionActive(paywallManager.isSubscribed)
        }
        .onChange(of: paywallManager.isSubscribed) { _, isSubscribed in
            playerViewModel.setSubscriptionActive(isSubscribed)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await paywallManager.refreshSubscriptionStatus()
            }
        }
        .task {
            await paywallManager.refreshSubscriptionStatus()
            playerViewModel.setSubscriptionActive(paywallManager.isSubscribed)
        }
        .task {
            guard isShowingSplash else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.55)) {
                isShowingSplash = false
            }
        }
    }
}
