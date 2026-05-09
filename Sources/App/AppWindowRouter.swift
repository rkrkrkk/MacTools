import AppKit
import SwiftUI

@MainActor
final class AppWindowRouter {
    private let pluginHost: PluginHost
    private let appUpdater: AppUpdater
    private let menuBarIconSettings: MenuBarIconSettings
    private var settingsWindow: NSWindow?

    init(
        pluginHost: PluginHost,
        appUpdater: AppUpdater,
        menuBarIconSettings: MenuBarIconSettings
    ) {
        self.pluginHost = pluginHost
        self.appUpdater = appUpdater
        self.menuBarIconSettings = menuBarIconSettings
    }

    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        show(window)
        settingsWindow = window
    }

    private func show(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.minSize = NSSize(width: 860, height: 560)
        window.contentView = NSHostingView(
            rootView: SettingsView(
                pluginHost: pluginHost,
                appUpdater: appUpdater,
                menuBarIconSettings: menuBarIconSettings
            )
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
