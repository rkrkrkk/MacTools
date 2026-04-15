import AppKit
import SwiftUI
import XCTest
@testable import MacTools

final class MenuBarPanelLayoutTests: XCTestCase {
    func testBaseWidthRemainsFixedForCompactPanelPresentation() {
        XCTAssertEqual(MenuBarPanelLayout.baseWidth, 296)
    }

    func testSurfaceWidthStaysAtBaseCardWidthWhenSecondaryPanelIsVisible() {
        XCTAssertEqual(
            MenuBarPanelLayout.surfaceWidth,
            MenuBarPanelLayout.baseWidth - (MenuBarPanelLayout.outerPadding * 2)
        )
    }

    func testWidthUsesBaseWidthWhenNoSecondaryPanelIsVisible() {
        let item = makeItem(controlStyle: .disclosure, isExpanded: true, secondaryPanel: nil)

        XCTAssertEqual(MenuBarPanelLayout.width(for: [item]), MenuBarPanelLayout.baseWidth)
    }

    func testWidthAddsSecondaryPanelWidthForExpandedDisclosurePanel() {
        let item = makeItem(
            controlStyle: .disclosure,
            isExpanded: true,
            secondaryPanel: PluginPanelSecondaryPanel(title: "Studio Display", controls: [])
        )

        XCTAssertEqual(MenuBarPanelLayout.width(for: [item]), MenuBarPanelLayout.baseWidth)
    }

    func testWidthIgnoresSecondaryPanelForCollapsedDisclosurePanel() {
        let item = makeItem(
            controlStyle: .disclosure,
            isExpanded: false,
            secondaryPanel: PluginPanelSecondaryPanel(title: "Studio Display", controls: [])
        )

        XCTAssertEqual(MenuBarPanelLayout.width(for: [item]), MenuBarPanelLayout.baseWidth)
    }

    private func makeItem(
        controlStyle: PluginControlStyle,
        isExpanded: Bool,
        secondaryPanel: PluginPanelSecondaryPanel?
    ) -> PluginPanelItem {
        PluginPanelItem(
            id: "display-resolution",
            title: "显示器分辨率",
            iconName: "display",
            iconTint: Color(nsColor: .systemBlue),
            controlStyle: controlStyle,
            menuActionBehavior: .keepPresented,
            description: "查看并切换每个显示器的分辨率",
            helpText: "查看并切换每个显示器的分辨率",
            descriptionTone: .secondary,
            isOn: false,
            isExpanded: isExpanded,
            isEnabled: true,
            detail: PluginPanelDetail(primaryControls: [], secondaryPanel: secondaryPanel)
        )
    }
}

@MainActor
final class HoverSecondaryPanelCoordinatorTests: XCTestCase {
    func testSwitchingActivationClearsPreviousAnchor() {
        let coordinator = HoverSecondaryPanelCoordinator(dismissDelay: .milliseconds(5))

        coordinator.hoverBegan(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "2"
        )
        coordinator.setSelectedRowFrame(CGRect(x: 10, y: 20, width: 30, height: 40))

        coordinator.hoverBegan(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "3"
        )

        XCTAssertEqual(
            coordinator.activeActivation,
            HoverSecondaryPanelCoordinator.Activation(
                pluginID: "display-resolution",
                controlID: "display-navigation",
                optionID: "3"
            )
        )
        XCTAssertNil(coordinator.selectedRowFrame)
    }

    func testHoverEndDismissesAfterDelayAndNotifies() async throws {
        let coordinator = HoverSecondaryPanelCoordinator(dismissDelay: .milliseconds(10))
        var dismissedActivation: HoverSecondaryPanelCoordinator.Activation?

        coordinator.onDismissRequest = { activation in
            dismissedActivation = activation
        }

        coordinator.hoverBegan(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "2"
        )
        coordinator.setSelectedRowFrame(CGRect(x: 1, y: 2, width: 3, height: 4))
        coordinator.hoverEnded(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "2"
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(coordinator.activeActivation)
        XCTAssertNil(coordinator.selectedRowFrame)
        XCTAssertEqual(
            dismissedActivation,
            HoverSecondaryPanelCoordinator.Activation(
                pluginID: "display-resolution",
                controlID: "display-navigation",
                optionID: "2"
            )
        )
    }

    func testPanelHoverCancelsPendingDismissal() async throws {
        let coordinator = HoverSecondaryPanelCoordinator(dismissDelay: .milliseconds(20))
        var dismissCount = 0

        coordinator.onDismissRequest = { _ in
            dismissCount += 1
        }

        coordinator.hoverBegan(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "2"
        )
        coordinator.hoverEnded(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: "2"
        )
        coordinator.setPanelHovered(true)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(coordinator.activeActivation)
        XCTAssertEqual(dismissCount, 0)

        coordinator.setPanelHovered(false)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(coordinator.activeActivation)
        XCTAssertEqual(dismissCount, 1)
    }
}
