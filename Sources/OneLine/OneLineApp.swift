import SwiftUI
import CoreText
import AppKit
import Sparkle

@main
struct OneLineApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        registerFont()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 680)

        Settings {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }
}

private func registerFont() {
    guard let fontURL = Bundle.main.url(forResource: "RobotoMono-VariableFont_wght", withExtension: "ttf") else {
        return
    }
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
}
