import AppKit
import CoreGraphics
import Foundation

final class SystemDisplayBrightnessBackendBuilder: DisplayBrightnessBackendBuilding {
    typealias Arm64ServiceResolver = ([DisplayInfo]) -> [CGDirectDisplayID: CFTypeRef]
    typealias AppleBackendFactory = (DisplayInfo) -> (any DisplayBrightnessBackend)?
    typealias DDCBackendFactory = (DisplayInfo, CFTypeRef?) -> (any DisplayBrightnessBackend)?
    typealias SoftwareBackendFactory = (DisplayInfo) -> (any DisplayBrightnessBackend)?

    private let resolveArm64Services: Arm64ServiceResolver
    private let appleFactory: AppleBackendFactory
    private let ddcFactory: DDCBackendFactory
    private let gammaFactory: SoftwareBackendFactory
    private let shadeFactory: SoftwareBackendFactory

    init(
        displayProvider: DisplayProviding,
        resolveArm64Services: @escaping Arm64ServiceResolver = Arm64DDCServiceMatcher.resolveServices,
        appleFactory: AppleBackendFactory? = nil,
        ddcFactory: DDCBackendFactory? = nil,
        gammaFactory: SoftwareBackendFactory? = nil,
        shadeFactory: SoftwareBackendFactory? = nil
    ) {
        let displayServicesBridge = DisplayServicesBrightnessBridge()
        _ = displayProvider

        self.resolveArm64Services = resolveArm64Services
        self.appleFactory = appleFactory ?? { display in
            guard let backend = AppleNativeBrightnessBackend(
                display: display,
                bridge: displayServicesBridge
            ) else {
                return nil
            }

            do {
                _ = try backend.readBrightness()
                return backend
            } catch {
                return nil
            }
        }
        self.ddcFactory = ddcFactory ?? { display, matchedService in
            if let transport = Arm64DDCTransport(display: display, service: matchedService) {
                return DDCBrightnessBackend(display: display, transport: transport)
            }

            if let transport = IntelDDCTransport(display: display) {
                return DDCBrightnessBackend(display: display, transport: transport)
            }

            return nil
        }
        self.gammaFactory = gammaFactory ?? { display in
            GammaBrightnessBackend(display: display)
        }
        self.shadeFactory = shadeFactory ?? { display in
            ShadeBrightnessBackend(display: display)
        }
    }

    func backends(
        for displays: [DisplayInfo],
        previous: [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend] {
        let arm64Services = resolveArm64Services(displays)
        var result: [CGDirectDisplayID: any DisplayBrightnessBackend] = [:]

        for display in displays {
            if let backend = reuse(previous[display.id], kind: .appleNative, display: display)
                ?? appleFactory(display) {
                result[display.id] = backend
                continue
            }

            if let backend = reuse(previous[display.id], kind: .ddc, display: display)
                ?? ddcFactory(display, arm64Services[display.id]) {
                result[display.id] = backend
                continue
            }

            if let backend = reuse(previous[display.id], kind: .gamma, display: display)
                ?? gammaFactory(display) {
                result[display.id] = backend
                continue
            }

            if let backend = reuse(previous[display.id], kind: .shade, display: display)
                ?? shadeFactory(display) {
                result[display.id] = backend
            }
        }

        return result
    }

    private func reuse(
        _ previous: (any DisplayBrightnessBackend)?,
        kind: DisplayBrightnessBackendKind,
        display: DisplayInfo
    ) -> (any DisplayBrightnessBackend)? {
        guard let backend = previous, backend.kind == kind else {
            return nil
        }

        backend.display = display
        return backend
    }
}

final class AppleNativeBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    let kind: DisplayBrightnessBackendKind = .appleNative
    var display: DisplayInfo

    private let bridge: DisplayServicesBrightnessBridge

    init?(
        display: DisplayInfo,
        bridge: DisplayServicesBrightnessBridge
    ) {
        guard display.isAppleDisplay else {
            return nil
        }

        self.display = display
        self.bridge = bridge
    }

    func readBrightness() throws -> Double {
        try bridge.readBrightness(displayID: display.id)
    }

    func writeBrightness(_ value: Double) throws {
        try bridge.writeBrightness(value, displayID: display.id)
    }

    func cleanup() {}
}

final class DDCBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    let kind: DisplayBrightnessBackendKind = .ddc
    var display: DisplayInfo

    private let transport: any DDCBrightnessTransport
    private var maximumValue: UInt16

    init?(display: DisplayInfo, transport: any DDCBrightnessTransport) {
        guard !display.isBuiltin else {
            return nil
        }

        do {
            let brightness = try transport.readBrightness()
            self.display = display
            self.transport = transport
            self.maximumValue = brightness.maximum
        } catch {
            return nil
        }
    }

    func readBrightness() throws -> Double {
        let brightness = try transport.readBrightness()
        maximumValue = brightness.maximum
        return maximumValue == 0 ? 1 : Double(brightness.current) / Double(maximumValue)
    }

    func writeBrightness(_ value: Double) throws {
        let clampedValue = max(0, min(value, 1))
        let rawValue = UInt16((Double(maximumValue) * clampedValue).rounded())
        try transport.writeBrightness(rawValue)
    }

    func cleanup() {}
}

final class GammaBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    private struct TransferTable {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    let kind: DisplayBrightnessBackendKind = .gamma
    var display: DisplayInfo

    private var originalTransferTable: TransferTable?
    private var currentBrightness = 1.0

    init?(display: DisplayInfo) {
        guard Self.canControl(displayID: display.id) else {
            return nil
        }

        self.display = display
    }

    func readBrightness() throws -> Double {
        currentBrightness
    }

    func writeBrightness(_ value: Double) throws {
        let clampedValue = max(0, min(value, 1))
        let transferTable = try loadOriginalTransferTableIfNeeded()
        let red = transferTable.red.map { $0 * Float(clampedValue) }
        let green = transferTable.green.map { $0 * Float(clampedValue) }
        let blue = transferTable.blue.map { $0 * Float(clampedValue) }

        let result = CGSetDisplayTransferByTable(
            display.id,
            UInt32(red.count),
            red,
            green,
            blue
        )

        guard result == .success else {
            throw DisplayBrightnessControllerError.failed(message: "软件亮度调节失败")
        }

        currentBrightness = clampedValue
    }

    func cleanup() {
        guard let originalTransferTable else {
            return
        }

        _ = CGSetDisplayTransferByTable(
            display.id,
            UInt32(originalTransferTable.red.count),
            originalTransferTable.red,
            originalTransferTable.green,
            originalTransferTable.blue
        )
        currentBrightness = 1
    }

    private func loadOriginalTransferTableIfNeeded() throws -> TransferTable {
        if let originalTransferTable {
            return originalTransferTable
        }

        var sampleCount: UInt32 = 0
        let countResult = CGGetDisplayTransferByTable(display.id, 0, nil, nil, nil, &sampleCount)

        guard countResult == .success, sampleCount > 0 else {
            throw DisplayBrightnessControllerError.brightnessUnavailable(displayName: display.name)
        }

        let red = UnsafeMutablePointer<CGGammaValue>.allocate(capacity: Int(sampleCount))
        let green = UnsafeMutablePointer<CGGammaValue>.allocate(capacity: Int(sampleCount))
        let blue = UnsafeMutablePointer<CGGammaValue>.allocate(capacity: Int(sampleCount))
        defer {
            red.deallocate()
            green.deallocate()
            blue.deallocate()
        }

        let readResult = CGGetDisplayTransferByTable(
            display.id,
            sampleCount,
            red,
            green,
            blue,
            &sampleCount
        )

        guard readResult == .success else {
            throw DisplayBrightnessControllerError.brightnessUnavailable(displayName: display.name)
        }

        let transferTable = TransferTable(
            red: Array(UnsafeBufferPointer(start: red, count: Int(sampleCount))),
            green: Array(UnsafeBufferPointer(start: green, count: Int(sampleCount))),
            blue: Array(UnsafeBufferPointer(start: blue, count: Int(sampleCount)))
        )
        originalTransferTable = transferTable
        return transferTable
    }

    private static func canControl(displayID: CGDirectDisplayID) -> Bool {
        var sampleCount: UInt32 = 0
        return CGGetDisplayTransferByTable(displayID, 0, nil, nil, nil, &sampleCount) == .success
            && sampleCount > 0
    }
}

final class ShadeBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    let kind: DisplayBrightnessBackendKind = .shade
    var display: DisplayInfo

    private let overlayController = ShadeOverlayController()
    private var currentBrightness = 1.0

    init?(display: DisplayInfo) {
        guard Self.screen(for: display.id) != nil else {
            return nil
        }

        self.display = display
    }

    func readBrightness() throws -> Double {
        refreshOverlayFrameIfNeeded()
        return currentBrightness
    }

    func writeBrightness(_ value: Double) throws {
        let clampedValue = max(0, min(value, 1))
        guard Self.screen(for: display.id) != nil else {
            throw DisplayBrightnessControllerError.displayUnavailable(displayID: display.id)
        }

        applyOverlay(brightness: clampedValue)
        currentBrightness = clampedValue
    }

    func cleanup() {
        hideOverlay()
        currentBrightness = 1
    }

    private func refreshOverlayFrameIfNeeded() {
        guard currentBrightness < 0.999, Self.screen(for: display.id) != nil else {
            return
        }

        applyOverlay(brightness: currentBrightness)
    }

    private func applyOverlay(brightness: Double) {
        let displayID = display.id
        let overlayController = self.overlayController

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                guard let screen = Self.screen(for: displayID) else {
                    return
                }

                overlayController.apply(brightness: brightness, on: screen)
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let screen = Self.screen(for: displayID) else {
                    return
                }

                overlayController.apply(brightness: brightness, on: screen)
            }
        }
    }

    private func hideOverlay() {
        let overlayController = self.overlayController

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                overlayController.hide()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                overlayController.hide()
            }
        }
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })
    }
}

@MainActor
private final class ShadeOverlayController {
    private var window: NSWindow?

    func apply(brightness: Double, on screen: NSScreen) {
        let alpha = max(0, min(1 - brightness, 0.92))

        guard alpha > 0.001 else {
            hide()
            return
        }

        let window = self.window ?? self.makeWindow(screen: screen)
        window.setFrame(screen.frame, display: true)
        window.alphaValue = alpha
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        guard let window else {
            return
        }

        window.orderOut(nil)
        self.window = nil
    }

    private func makeWindow(screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        return window
    }
}

final class DisplayServicesBrightnessBridge: @unchecked Sendable {
    private typealias GetBrightnessFunction = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightnessFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getBrightness: GetBrightnessFunction?
    private let setBrightness: SetBrightnessFunction?

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        )
        self.getBrightness = Self.loadSymbol("DisplayServicesGetBrightness", from: handle)
        self.setBrightness = Self.loadSymbol("DisplayServicesSetBrightness", from: handle)
    }

    func readBrightness(displayID: CGDirectDisplayID) throws -> Double {
        guard let getBrightness else {
            throw DisplayBrightnessControllerError.nativeAPINotAvailable
        }

        var value: Float = 0
        guard getBrightness(displayID, &value) == 0 else {
            throw DisplayBrightnessControllerError.brightnessUnavailable(displayName: "显示器")
        }

        return Double(max(0, min(value, 1)))
    }

    func writeBrightness(_ value: Double, displayID: CGDirectDisplayID) throws {
        guard let setBrightness else {
            throw DisplayBrightnessControllerError.nativeAPINotAvailable
        }

        guard setBrightness(displayID, Float(max(0, min(value, 1)))) == 0 else {
            throw DisplayBrightnessControllerError.failed(message: "原生亮度写入失败")
        }
    }

    private static func loadSymbol<T>(
        _ symbol: String,
        from handle: UnsafeMutableRawPointer?
    ) -> T? {
        guard let symbolPointer = dlsym(handle, symbol) else {
            return nil
        }

        return unsafeBitCast(symbolPointer, to: T.self)
    }
}
