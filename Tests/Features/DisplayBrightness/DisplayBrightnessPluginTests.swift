import XCTest
@testable import MacTools

@MainActor
final class DisplayBrightnessPluginTests: XCTestCase {
    func testParseDisplayIDExtractsNumericIdentifier() {
        XCTAssertEqual(
            DisplayBrightnessPlugin.parseDisplayID(from: "display.42.brightness"),
            42
        )
    }

    func testParseDisplayIDRejectsUnexpectedControlID() {
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "display.42"))
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "brightness.42"))
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "display.foo.brightness"))
    }

    func testEmptySnapshotDisablesPluginAndSuppressesDetail() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(displays: [], errorMessage: nil)

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))

        let state = plugin.panelState

        XCTAssertEqual(state.subtitle, "未检测到可调节亮度的显示器")
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.detail)
    }

    func testSingleDisplaySummaryIncludesDisplayNameAndBrightness() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.panelState.subtitle, "Studio Display 72%")
    }

    func testMultipleDisplaysSummaryUsesDisplayCount() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72),
                makeBrightnessDisplay(id: 9, name: "LG UltraFine", brightness: 0.41, backendKind: .ddc)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.panelState.subtitle, "2 个显示器")
    }

    func testExpandedStateBuildsOneSliderPerDisplay() throws {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72),
                makeBrightnessDisplay(id: 9, name: "LG UltraFine", brightness: 0.41, backendKind: .ddc)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))

        let controls = try XCTUnwrap(plugin.panelState.detail?.primaryControls)

        XCTAssertEqual(controls.count, 2)
        XCTAssertEqual(controls.map(\.kind), [.slider, .slider])
        XCTAssertEqual(controls.map(\.id), ["display.7.brightness", "display.9.brightness"])
        XCTAssertEqual(controls.map(\.sectionTitle), ["Studio Display", "LG UltraFine"])
        XCTAssertEqual(controls.map(\.valueLabel), ["72%", "41%"])
        XCTAssertEqual(controls.first?.sliderBounds, 0...1)
        XCTAssertEqual(controls.first?.sliderStep, 0.01)
    }

    func testErrorMessageIsExposedFromSnapshot() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72)
            ],
            errorMessage: "调节失败：DDC 写入失败"
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.panelState.errorMessage, "调节失败：DDC 写入失败")
    }
}
