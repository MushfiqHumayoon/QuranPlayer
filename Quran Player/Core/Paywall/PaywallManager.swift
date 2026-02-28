//
//  PaywallManager.swift
//  Quran Player
//
//  Created by Codex on 20/02/26.
//

import Adapty
import AdaptyUI
import Combine
import Foundation
import StoreKit

@MainActor
final class PaywallManager: ObservableObject {
    struct PresentationError: Identifiable {
        let id = UUID()
        let message: String
    }

    @Published var isPresented = false
    @Published private(set) var isLoading = false
    @Published private(set) var paywallConfiguration: AdaptyUI.PaywallConfiguration?
    @Published private(set) var isSubscribed = false
    @Published var presentationError: PresentationError?

    private let placementId: String

    init(placementId: String = "main") {
        self.placementId = placementId
    }

    func presentPaywall() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            defer { isLoading = false }
            var requestedProductIDs: [String] = []
            let diagnostics = runtimeDiagnostics

            do {
                let paywall = try await Adapty.getPaywall(placementId: placementId)
                let vendorProductIds = paywall.vendorProductIds
                requestedProductIDs = vendorProductIds

                guard paywall.hasViewConfiguration else {
                    report(
                        message: "Placement \"\(placementId)\" returned a paywall without a Paywall Builder configuration."
                    )
                    return
                }

                guard !vendorProductIds.isEmpty else {
                    report(
                        message: "No product IDs found in placement \"\(placementId)\". Add products to the paywall in Adapty Dashboard."
                    )
                    return
                }

                let storeKitProducts = try await Product.products(for: vendorProductIds)
                guard !storeKitProducts.isEmpty else {
                    report(
                        message:
                            "Direct StoreKit lookup returned no products for placement \"\(placementId)\". Product IDs: \(vendorProductIds.joined(separator: ", ")). \(diagnostics)"
                    )
                    return
                }

                let resolvedStoreKitIDs = Set(storeKitProducts.map(\.id))
                let missingStoreKitIDs = vendorProductIds.filter { !resolvedStoreKitIDs.contains($0) }
                if !missingStoreKitIDs.isEmpty {
                    report(
                        message:
                            "StoreKit resolved only \(storeKitProducts.count)/\(vendorProductIds.count) products. Missing IDs: \(missingStoreKitIDs.joined(separator: ", ")). \(diagnostics)"
                    )
                    return
                }

                let products = try await Adapty.getPaywallProducts(paywall: paywall)
                paywallConfiguration = try await AdaptyUI.getPaywallConfiguration(
                    forPaywall: paywall,
                    products: products
                )
                isPresented = true
            } catch let adaptyError as AdaptyError where adaptyError.adaptyErrorCode == .noProductIDsFound {
                let productIDsSummary = requestedProductIDs.isEmpty ? "none" : requestedProductIDs.joined(separator: ", ")
                report(
                    message:
                        "StoreKit returned no products for placement \"\(placementId)\". Product IDs: \(productIDsSummary). Verify IDs are correct in Adapty, exist in App Store Connect for this app, and are available for the current sandbox account. \(diagnostics)"
                )
            } catch {
                report(error)
            }
        }
    }

    func handleFailedPurchase(_ error: AdaptyError) {
        report(error)
    }

    func handleDidFinishPurchase(_ result: AdaptyPurchaseResult) {
        guard let profile = result.profile else { return }
        updateSubscriptionStatus(with: profile)
    }

    func handleFailedRestore(_ error: AdaptyError) {
        report(error)
    }

    func handleDidFinishRestore(_ profile: AdaptyProfile) {
        updateSubscriptionStatus(with: profile)
    }

    func refreshSubscriptionStatus() async {
        do {
            let profile = try await Adapty.getProfile()
            updateSubscriptionStatus(with: profile)
        } catch {
            // Keep the last known entitlement state if profile refresh fails.
        }
    }

    func handleFailedRendering(_ error: AdaptyUIError) {
        isPresented = false
        report(error)
    }

    private func updateSubscriptionStatus(with profile: AdaptyProfile) {
        isSubscribed = profile.accessLevels.values.contains(where: \.isActive)
    }

    private func report(_ error: Error) {
        presentationError = PresentationError(message: error.localizedDescription)
    }

    private func report(message: String) {
        presentationError = PresentationError(message: message)
    }

    private var runtimeDiagnostics: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        #if targetEnvironment(simulator)
        let runtime = "simulator"
        #else
        let runtime = "device"
        #endif
        return "Bundle: \(bundleId). Runtime: \(runtime). canMakePayments: \(AppStore.canMakePayments)."
    }
}
