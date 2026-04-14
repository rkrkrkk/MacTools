import AppKit
import SwiftUI

@main
struct MacToolsApp: App {
    @StateObject private var pluginHost = PluginHost()

    var body: some Scene {
        MenuBarExtra("MacTools", systemImage: menuBarSymbolName) {
            MenuBarContent(pluginHost: pluginHost)
                .frame(width: 304)
                .onAppear {
                    pluginHost.refreshAll()
                }
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView(pluginHost: pluginHost)
        }
        .defaultSize(width: 480, height: 320)
        .windowResizability(.contentSize)
    }

    private var menuBarSymbolName: String {
        pluginHost.hasActivePlugin
            ? "sparkles.rectangle.stack.fill"
            : "sparkles.rectangle.stack"
    }
}
