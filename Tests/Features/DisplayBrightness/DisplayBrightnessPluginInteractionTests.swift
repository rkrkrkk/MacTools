import XCTest
@testable import MacTools

@MainActor
final class DisplayBrightnessPluginInteractionTests: XCTestCase {
    func testExpandingPluginRefreshesController() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))

        XCTAssertEqual(controller.refreshCount, 1)
        XCTAssertTrue(plugin.panelState.isExpanded)
    }

    func testSliderChangedForwardsDraftBrightnessValue() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(
            .setSlider(controlID: "display.2.brightness", value: 0.34, phase: .changed)
        )

        XCTAssertEqual(
            controller.setBrightnessCalls,
            [.init(value: 0.34, displayID: 2, phase: .changed)]
        )
    }

    func testSliderEndedForwardsFinalBrightnessValue() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(
            .setSlider(controlID: "display.2.brightness", value: 0.8, phase: .ended)
        )

        XCTAssertEqual(
            controller.setBrightnessCalls,
            [.init(value: 0.8, displayID: 2, phase: .ended)]
        )
    }

    func testInvalidSliderControlIDIsIgnored() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(
            .setSlider(controlID: "display.invalid", value: 0.8, phase: .ended)
        )

        XCTAssertTrue(controller.setBrightnessCalls.isEmpty)
    }
}
