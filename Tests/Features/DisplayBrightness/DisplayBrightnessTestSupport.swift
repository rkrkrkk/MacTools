import AppKit
import CoreGraphics
import Foundation
@testable import MacTools

func makeTestDisplay(
    id: CGDirectDisplayID,
    name: String,
    isBuiltin: Bool = false,
    isMain: Bool = false,
    vendorNumber: UInt32? = nil,
    modelNumber: UInt32? = nil,
    serialNumber: UInt32? = nil
) -> DisplayInfo {
    DisplayInfo(
        id: id,
        name: name,
        isBuiltin: isBuiltin,
        isMain: isMain,
        vendorNumber: vendorNumber,
        modelNumber: modelNumber,
        serialNumber: serialNumber
    )
}

func makeBrightnessDisplay(
    id: CGDirectDisplayID,
    name: String,
    brightness: Double,
    backendKind: DisplayBrightnessBackendKind = .appleNative,
    isPendingWrite: Bool = false
) -> DisplayBrightnessDisplay {
    DisplayBrightnessDisplay(
        display: makeTestDisplay(id: id, name: name),
        brightness: brightness,
        backendKind: backendKind,
        isPendingWrite: isPendingWrite
    )
}

@MainActor
final class MockDisplayBrightnessController: DisplayBrightnessControlling {
    struct SetBrightnessCall: Equatable {
        let value: Double
        let displayID: CGDirectDisplayID
        let phase: PluginPanelAction.SliderPhase
    }

    var onStateChange: (() -> Void)?
    var snapshotValue = DisplayBrightnessSnapshot(displays: [], errorMessage: nil)
    var refreshCount = 0
    var setBrightnessCalls: [SetBrightnessCall] = []

    func refresh() {
        refreshCount += 1
    }

    func snapshot() -> DisplayBrightnessSnapshot {
        snapshotValue
    }

    func setBrightness(
        _ value: Double,
        for displayID: CGDirectDisplayID,
        phase: PluginPanelAction.SliderPhase
    ) {
        setBrightnessCalls.append(
            SetBrightnessCall(value: value, displayID: displayID, phase: phase)
        )
    }
}

final class StubDisplayProvider: DisplayProviding {
    var displays: [DisplayInfo]

    init(displays: [DisplayInfo] = []) {
        self.displays = displays
    }

    func listConnectedDisplays() -> [DisplayInfo] {
        displays
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        nil
    }
}

final class StubBrightnessBackendBuilder: DisplayBrightnessBackendBuilding {
    typealias BuildHandler = (
        [DisplayInfo],
        [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend]

    var handler: BuildHandler
    private(set) var calls: [[DisplayInfo]] = []

    init(handler: @escaping BuildHandler = { _, _ in [:] }) {
        self.handler = handler
    }

    func backends(
        for displays: [DisplayInfo],
        previous: [CGDirectDisplayID: any DisplayBrightnessBackend]
    ) -> [CGDirectDisplayID: any DisplayBrightnessBackend] {
        calls.append(displays)
        return handler(displays, previous)
    }
}

final class TestBrightnessBackend: DisplayBrightnessBackend, @unchecked Sendable {
    let kind: DisplayBrightnessBackendKind
    var display: DisplayInfo

    var writeDelay: TimeInterval = 0
    var blockFirstWrite = false
    let firstWriteStarted = DispatchSemaphore(value: 0)
    let allowFirstWriteToFinish = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var storedBrightness: Double
    private var pendingWriteErrors: [Error] = []
    private var recordedWritesStorage: [Double] = []
    private var cleanupCountStorage = 0
    private var writeCountStorage = 0
    private var activeWrites = 0
    private var maxConcurrentWritesStorage = 0

    init(
        kind: DisplayBrightnessBackendKind,
        display: DisplayInfo,
        brightness: Double = 1
    ) {
        self.kind = kind
        self.display = display
        self.storedBrightness = brightness
    }

    var recordedWrites: [Double] {
        lock.withLock { recordedWritesStorage }
    }

    var cleanupCount: Int {
        lock.withLock { cleanupCountStorage }
    }

    var writeCount: Int {
        lock.withLock { writeCountStorage }
    }

    var maxConcurrentWrites: Int {
        lock.withLock { maxConcurrentWritesStorage }
    }

    func enqueueWriteError(_ error: Error) {
        lock.withLock {
            pendingWriteErrors.append(error)
        }
    }

    func readBrightness() throws -> Double {
        lock.withLock { storedBrightness }
    }

    func writeBrightness(_ value: Double) throws {
        let shouldBlock = lock.withLock { () -> Bool in
            writeCountStorage += 1
            recordedWritesStorage.append(value)
            activeWrites += 1
            maxConcurrentWritesStorage = max(maxConcurrentWritesStorage, activeWrites)
            return blockFirstWrite && writeCountStorage == 1
        }

        defer {
            lock.withLock {
                activeWrites -= 1
            }
        }

        if shouldBlock {
            firstWriteStarted.signal()
            allowFirstWriteToFinish.wait()
        }

        if writeDelay > 0 {
            Thread.sleep(forTimeInterval: writeDelay)
        }

        if let error = lock.withLock({
            pendingWriteErrors.isEmpty ? nil : pendingWriteErrors.removeFirst()
        }) {
            throw error
        }

        lock.withLock {
            storedBrightness = value
        }
    }

    func cleanup() {
        lock.withLock {
            cleanupCountStorage += 1
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
