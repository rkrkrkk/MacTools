import CoreGraphics
import XCTest
@testable import MacTools

@MainActor
final class DisplayResolutionPluginSidePanelTests: XCTestCase {
    func testExpandedStateShowsDisplayNavigationAndNoSecondaryPanelByDefault() throws {
        let plugin = makePlugin()
        plugin.handlePanelAction(.setDisclosureExpanded(true))

        let detail = try XCTUnwrap(plugin.panelState.detail)

        XCTAssertEqual(detail.primaryControls.count, 1)
        XCTAssertEqual(detail.primaryControls[0].kind, .navigationList)
        XCTAssertNil(detail.secondaryPanel)
    }

    func testSelectingDisplayShowsSecondaryPanel() throws {
        let plugin = makePlugin()
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        let secondary = try XCTUnwrap(plugin.panelState.detail?.secondaryPanel)
        XCTAssertEqual(secondary.title, "Studio Display")
        XCTAssertEqual(secondary.controls.first?.kind, .selectList)
    }

    func testSelectingSameDisplayTwiceClosesSecondaryPanel() {
        let plugin = makePlugin()
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))
        plugin.handlePanelAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        XCTAssertNil(plugin.panelState.detail?.secondaryPanel)
    }

    func testCollapsingPluginClearsSelectedDisplay() {
        let plugin = makePlugin()
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))
        plugin.handlePanelAction(.setDisclosureExpanded(false))

        XCTAssertNil(plugin.panelState.detail)
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        XCTAssertNil(plugin.panelState.detail?.secondaryPanel)
    }

    func testMissingSelectedDisplayClearsSecondaryPanel() {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            DisplayInfo(id: 2, name: "Studio Display", isBuiltin: false, isMain: true)
        ]
        controller.modesByDisplayID = [2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)]]

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handlePanelAction(.setDisclosureExpanded(true))
        plugin.handlePanelAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        controller.displays = []

        XCTAssertNil(plugin.panelState.detail?.secondaryPanel)
    }

    private func makePlugin() -> DisplayResolutionPlugin {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            DisplayInfo(id: 2, name: "Studio Display", isBuiltin: false, isMain: true),
            DisplayInfo(id: 3, name: "LG UltraFine", isBuiltin: false, isMain: false)
        ]
        controller.modesByDisplayID = [
            2: [
                makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true),
                makeMode(modeId: 12, width: 2560, height: 1440)
            ],
            3: [
                makeMode(modeId: 30, width: 3008, height: 1692, isCurrent: true)
            ]
        ]
        return DisplayResolutionPlugin(controller: controller)
    }

    private func makeMode(
        modeId: Int32,
        width: Int,
        height: Int,
        isCurrent: Bool = false
    ) -> DisplayResolutionInfo {
        DisplayResolutionInfo(
            modeId: modeId,
            width: width,
            height: height,
            pixelWidth: width * 2,
            pixelHeight: height * 2,
            refreshRate: 60,
            isHiDPI: true,
            isNative: false,
            isDefault: false,
            isCurrent: isCurrent
        )
    }
}

@MainActor
private final class MockDisplayResolutionController: DisplayResolutionControlling {
    var displays: [DisplayInfo] = []
    var modesByDisplayID: [CGDirectDisplayID: [DisplayResolutionInfo]] = [:]

    func listConnectedDisplays() -> [DisplayInfo] { displays }

    func listAvailableResolutions(for displayID: CGDirectDisplayID) -> [DisplayResolutionInfo] {
        modesByDisplayID[displayID] ?? []
    }

    func applyResolution(
        _ info: DisplayResolutionInfo,
        for displayID: CGDirectDisplayID
    ) -> Result<Void, DisplayResolutionError> {
        .success(())
    }
}
