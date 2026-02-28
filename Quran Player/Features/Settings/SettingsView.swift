//
//  SettingsView.swift
//  Quran Player
//

import AdaptyUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var paywallManager: PaywallManager
    @ObservedObject var viewModel: HomeViewModel
    @AppStorage("isDarkMode") private var isDarkMode = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground(colorScheme: colorScheme)
                    .ignoresSafeArea()

                List {
                    subscriptionSection
                    reciterSection
//                    appearanceSection
                    aboutSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText(colorScheme))
                            .frame(width: 30, height: 30)
                            .background(.clear)
                            .clipShape(Circle())
                    }
                }
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
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            Button {
                if !paywallManager.isSubscribed {
                    paywallManager.presentPaywall()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: paywallManager.isSubscribed ? "checkmark.seal.fill" : "star.fill")
                        .font(.title2)
                        .foregroundStyle(
                            paywallManager.isSubscribed
                                ? AnyShapeStyle(Color.green)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(paywallManager.isSubscribed ? "Pro — Active" : "Upgrade to Pro")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText(colorScheme))

                        Text(
                            paywallManager.isSubscribed
                                ? "You have full access"
                                : "Unlock all features"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.tertiaryText(colorScheme))
                    }

                    Spacer()

                    if !paywallManager.isSubscribed {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.tertiaryText(colorScheme))
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(paywallManager.isSubscribed)
            .listRowBackground(AppTheme.cardBackground(colorScheme))
        }
    }

    // MARK: - Reciter

    private var reciterSection: some View {
        Section {
            NavigationLink {
                ReciterPickerView(viewModel: viewModel)
            } label: {
                HStack {
                    Label("Reciter", systemImage: "music.mic")
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                    Spacer()
                    Text(viewModel.selectedReciter?.displayName ?? "Select")
                        .foregroundStyle(AppTheme.tertiaryText(colorScheme))
                }
            }
            .listRowBackground(AppTheme.cardBackground(colorScheme))
        } header: {
            Text("Playback")
                .foregroundStyle(AppTheme.tertiaryText(colorScheme))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $isDarkMode) {
                Label("Dark Mode", systemImage: "moon.fill")
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
            }
            .tint(.green)
            .listRowBackground(AppTheme.cardBackground(colorScheme))
        } header: {
            Text("Appearance")
                .foregroundStyle(AppTheme.tertiaryText(colorScheme))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                Spacer()
                Text(appVersion)
                    .foregroundStyle(AppTheme.tertiaryText(colorScheme))
            }
            .listRowBackground(AppTheme.cardBackground(colorScheme))

            linkRow(title: "Contact Us", icon: "envelope", url: "mailto:apps.pumpkin@gmail.com")
            linkRow(
                title: "Privacy Policy",
                icon: "hand.raised",
                url: "https://www.notion.so/Privacy-Policy-8dd635a897e7424d807c68743b98201a"
            )
            linkRow(
                title: "Terms of Use",
                icon: "doc.text",
                url: "https://www.notion.so/Terms-of-Service-fbfbef30251542d7b7f25453a18cd531"
            )
        } header: {
            Text("About")
                .foregroundStyle(AppTheme.tertiaryText(colorScheme))
        }
    }

    private func linkRow(title: String, icon: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(AppTheme.primaryText(colorScheme))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText(colorScheme))
            }
        }
        .listRowBackground(AppTheme.cardBackground(colorScheme))
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Reciter Picker

private struct ReciterPickerView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AnimatedBackground(colorScheme: colorScheme)
                .ignoresSafeArea()

            List {
                ForEach(viewModel.reciters) { reciter in
                    Button {
                        viewModel.selectedReciterID = reciter.id
                    } label: {
                        HStack {
                            Text(reciter.displayName)
                                .foregroundStyle(AppTheme.primaryText(colorScheme))
                            Spacer()
                            if viewModel.selectedReciterID == reciter.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground(colorScheme))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Reciter")
        .navigationBarTitleDisplayMode(.inline)
    }
}
