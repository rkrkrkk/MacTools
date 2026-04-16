import CoreGraphics
import Foundation

enum DisplayBrightnessBackendKind: Equatable {
    case appleNative
    case ddc
    case gamma
    case shade
}

struct DisplayBrightnessDisplay: Identifiable, Equatable {
    let display: DisplayInfo
    let brightness: Double
    let backendKind: DisplayBrightnessBackendKind
    let isPendingWrite: Bool

    var id: CGDirectDisplayID { display.id }
}

struct DisplayBrightnessSnapshot: Equatable {
    let displays: [DisplayBrightnessDisplay]
    let errorMessage: String?
}

enum DisplayBrightnessControllerError: Error, LocalizedError {
    case displayUnavailable(displayID: CGDirectDisplayID)
    case brightnessUnavailable(displayName: String)
    case nativeAPINotAvailable
    case i2cUnavailable(displayName: String)
    case unsupportedReply(displayName: String)
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "显示器已断开连接"
        case .brightnessUnavailable(let displayName):
            return "\(displayName) 当前无法读取亮度"
        case .nativeAPINotAvailable:
            return "系统亮度接口不可用"
        case .i2cUnavailable(let displayName):
            return "\(displayName) 不支持 DDC/CI"
        case .unsupportedReply(let displayName):
            return "\(displayName) 返回了无效亮度数据"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
protocol DisplayBrightnessControlling: AnyObject {
    var onStateChange: (() -> Void)? { get set }

    func refresh()
    func snapshot() -> DisplayBrightnessSnapshot
    func setBrightness(
        _ value: Double,
        for displayID: CGDirectDisplayID,
        phase: PluginPanelAction.SliderPhase
    )
}

protocol DisplayBrightnessBackend: AnyObject, Sendable {
    var kind: DisplayBrightnessBackendKind { get }
    var display: DisplayInfo { get set }

    func readBrightness() throws -> Double
    func writeBrightness(_ value: Double) throws
    func cleanup()
}

protocol DisplayBrightnessBackendBuilding {
    func backends(
        for displays: [DisplayInfo],
        previous: [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend]
}
