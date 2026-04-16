import AppKit
import SwiftUI
import XCTest
@testable import MacTools

@MainActor
final class PluginHostSliderActionTests: XCTestCase {
    private let suiteName = "PluginHostSliderActionTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSetPanelSliderValueForwardsSliderAction() {
        let plugin = MockSliderPlugin()
        let host = makeHost(plugin: plugin)

        host.setPanelSliderValue(
            0.78,
            controlID: "display.2.brightness",
            for: plugin.manifest.id,
            phase: .ended
        )

        XCTAssertEqual(
            plugin.receivedActions,
            [.setSlider(controlID: "display.2.brightness", value: 0.78, phase: .ended)]
        )
    }

    private func makeHost(plugin: MockSliderPlugin) -> PluginHost {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return PluginHost(
            plugins: [plugin],
            shortcutStore: ShortcutStore(userDefaults: defaults),
            pluginDisplayPreferencesStore: PluginDisplayPreferencesStore(userDefaults: defaults),
            globalShortcutManager: GlobalShortcutManager()
        )
    }
}

@MainActor
private final class MockSliderPlugin: FeaturePlugin {
    let manifest = PluginManifest(
        id: "mock-slider",
        title: "Mock Slider",
        iconName: "sun.max",
        iconTint: Color(nsColor: .systemYellow),
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented,
        order: 1,
        defaultDescription: "Mock slider plugin"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var receivedActions: [PluginPanelAction] = []

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: "Mock",
            isOn: false,
            isExpanded: true,
            isEnabled: true,
            isVisible: true,
            detail: PluginPanelDetail(primaryControls: [], secondaryPanel: nil),
            errorMessage: nil
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {}

    func handlePanelAction(_ action: PluginPanelAction) {
        receivedActions.append(action)
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}
}
