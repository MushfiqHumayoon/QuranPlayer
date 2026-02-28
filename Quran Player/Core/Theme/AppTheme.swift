//
//  AppTheme.swift
//  Quran Player
//

import SwiftUI

struct AppTheme {
    // MARK: - Text

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(UIColor.label)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.72) : Color(UIColor.secondaryLabel)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.55) : Color(UIColor.tertiaryLabel)
    }

    // MARK: - Backgrounds

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color(UIColor.secondarySystemGroupedBackground)
    }

    static func buttonBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color(UIColor.systemGray5)
    }

    // MARK: - Borders & Separators

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color(UIColor.separator)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color(UIColor.separator)
    }

    // MARK: - Tint

    static func tintColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(UIColor.label)
    }

    // MARK: - Gradient Backgrounds

    static func backgroundGradientColors(_ scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color.black,
                Color(red: 0.03, green: 0.04, blue: 0.07),
                Color(red: 0.05, green: 0.06, blue: 0.10),
            ]
        } else {
            return [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.92, green: 0.93, blue: 0.96),
                Color(red: 0.90, green: 0.91, blue: 0.94),
            ]
        }
    }

    static func flowGradientColors(_ scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.02, green: 0.11, blue: 0.20),
                Color(red: 0.06, green: 0.15, blue: 0.11),
                Color(red: 0.09, green: 0.10, blue: 0.18),
                Color(red: 0.12, green: 0.12, blue: 0.14),
            ]
        } else {
            return [
                Color(red: 0.85, green: 0.90, blue: 0.98),
                Color(red: 0.88, green: 0.95, blue: 0.90),
                Color(red: 0.90, green: 0.88, blue: 0.96),
                Color(red: 0.92, green: 0.91, blue: 0.93),
            ]
        }
    }

    static func flowGradientOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.45 : 0.6
    }
}

// MARK: - Shared Animated Background

struct AnimatedBackground: View {
    let colorScheme: ColorScheme
    @State private var flowProgress = false

    var body: some View {
        let flowStart = UnitPoint(x: 0.5, y: flowProgress ? -0.15 : 1.15)
        let flowEnd = UnitPoint(x: 0.5, y: flowProgress ? 0.85 : 2.15)

        ZStack {
            LinearGradient(
                colors: AppTheme.backgroundGradientColors(colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: AppTheme.flowGradientColors(colorScheme),
                startPoint: flowStart,
                endPoint: flowEnd
            )
            .opacity(AppTheme.flowGradientOpacity(colorScheme))
            .blur(radius: 36)
        }
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
                flowProgress = true
            }
        }
    }
}
