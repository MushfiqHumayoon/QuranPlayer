//
//  Quran_PlayerApp.swift
//  Quran Player
//
//  Created by Mushfiq Humayoon on 20/02/26.
//

import SwiftUI
import Adapty
import AdaptyUI
internal import AdaptyLogger

@main
struct Quran_PlayerApp: App {
    init() {
        Adapty.activate("public_live_5KYRKTc7.plKtuygWd33C0ak8dWc4")
        AdaptyUI.activate()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
