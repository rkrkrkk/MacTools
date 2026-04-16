import AppKit
import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let vendorNumber: UInt32?
    let modelNumber: UInt32?
    let serialNumber: UInt32?

    var isAppleDisplay: Bool {
        isBuiltin
            || vendorNumber == 610
            || name.localizedCaseInsensitiveContains("apple")
            || name.localizedCaseInsensitiveContains("studio display")
            || name.localizedCaseInsensitiveContains("pro display")
    }
}

protocol DisplayProviding {
    func listConnectedDisplays() -> [DisplayInfo]
    func screen(for displayID: CGDirectDisplayID) -> NSScreen?
}

struct SystemDisplayService: DisplayProviding {
    func listConnectedDisplays() -> [DisplayInfo] {
        var activeCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &activeCount)

        let maxCount = max(activeCount, 16)
        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(maxCount))
        CGGetActiveDisplayList(maxCount, &displayIDs, &activeCount)

        return Array(displayIDs.prefix(Int(activeCount))).enumerated().compactMap { index, displayID in
            if CGDisplayIsInMirrorSet(displayID) != 0, CGDisplayIsMain(displayID) == 0 {
                return nil
            }

            let screen = screen(for: displayID)
            let name = screen?.localizedName ?? "Display \(index + 1)"
            let vendorNumber = CGDisplayVendorNumber(displayID)
            let modelNumber = CGDisplayModelNumber(displayID)
            let serialNumber = CGDisplaySerialNumber(displayID)

            return DisplayInfo(
                id: displayID,
                name: name,
                isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
                isMain: CGDisplayIsMain(displayID) != 0,
                vendorNumber: vendorNumber == 0 ? nil : vendorNumber,
                modelNumber: modelNumber == 0 ? nil : modelNumber,
                serialNumber: serialNumber == 0 ? nil : serialNumber
            )
        }
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })
    }
}
