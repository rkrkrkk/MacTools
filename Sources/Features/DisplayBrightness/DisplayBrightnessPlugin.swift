import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class DisplayBrightnessPlugin: FeaturePlugin {
    let manifest = PluginManifest(
        id: "display-brightness",
        title: "显示器亮度",
        iconName: "sun.max",
        iconTint: Color(nsColor: .systemYellow),
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented,
        order: 20,
        defaultDescription: "快速调节每个显示器的亮度"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let controller: DisplayBrightnessControlling
    private var isExpanded = false

    init(controller: DisplayBrightnessControlling = DisplayBrightnessController()) {
        self.controller = controller
        self.controller.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    var panelState: PluginPanelState {
        let snapshot = controller.snapshot()

        guard !snapshot.displays.isEmpty else {
            isExpanded = false
            return PluginPanelState(
                subtitle: "未检测到可调节亮度的显示器",
                isOn: false,
                isExpanded: false,
                isEnabled: false,
                isVisible: true,
                detail: nil,
                errorMessage: snapshot.errorMessage
            )
        }

        return PluginPanelState(
            subtitle: subtitle(for: snapshot.displays),
            isOn: false,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? buildDetail(for: snapshot.displays) : nil,
            errorMessage: snapshot.errorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        controller.refresh()
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value

            if value {
                controller.refresh()
            }

            onStateChange?()
        case let .setSlider(controlID, value, phase):
            guard let displayID = Self.parseDisplayID(from: controlID) else {
                AppLog.displayBrightnessPlugin.error(
                    "invalid slider control id \(controlID, privacy: .public)"
                )
                return
            }

            controller.setBrightness(value, for: displayID, phase: phase)
            onStateChange?()
        case .setSwitch,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate,
             .invokeAction:
            return
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    static func parseDisplayID(from controlID: String) -> CGDirectDisplayID? {
        let prefix = "display."
        let suffix = ".brightness"

        guard
            controlID.hasPrefix(prefix),
            controlID.hasSuffix(suffix)
        else {
            return nil
        }

        let startIndex = controlID.index(controlID.startIndex, offsetBy: prefix.count)
        let endIndex = controlID.index(controlID.endIndex, offsetBy: -suffix.count)
        return CGDirectDisplayID(controlID[startIndex..<endIndex])
    }

    private func subtitle(for displays: [DisplayBrightnessDisplay]) -> String {
        if displays.count == 1, let display = displays.first {
            return "\(display.display.name) \(Self.percentText(for: display.brightness))"
        }

        return "\(displays.count) 个显示器"
    }

    private func buildDetail(for displays: [DisplayBrightnessDisplay]) -> PluginPanelDetail {
        PluginPanelDetail(
            primaryControls: displays.map { display in
                PluginPanelControl(
                    id: "display.\(display.display.id).brightness",
                    kind: .slider,
                    options: [],
                    selectedOptionID: nil,
                    dateValue: nil,
                    minimumDate: nil,
                    displayedComponents: nil,
                    datePickerStyle: nil,
                    sectionTitle: display.display.name,
                    sliderValue: display.brightness,
                    sliderBounds: 0...1,
                    sliderStep: 0.01,
                    valueLabel: Self.percentText(for: display.brightness),
                    isEnabled: true
                )
            },
            secondaryPanel: nil
        )
    }

    private static func percentText(for brightness: Double) -> String {
        "\(Int((brightness * 100).rounded()))%"
    }
}
