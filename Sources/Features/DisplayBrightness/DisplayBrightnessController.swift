import AppKit
import CoreGraphics
import Foundation

private final class WeakBrightnessControllerRef: @unchecked Sendable {
    weak var value: DisplayBrightnessController?

    init(_ value: DisplayBrightnessController?) {
        self.value = value
    }
}

@MainActor
final class DisplayBrightnessController: DisplayBrightnessControlling {
    private struct ManagedDisplay {
        var display: DisplayInfo
        var backend: any DisplayBrightnessBackend
        var currentBrightness: Double
        var lastCommittedBrightness: Double
        var pendingBrightness: Double?
        var writeInFlight = false
        var scheduledFlush: DispatchWorkItem?
    }

    var onStateChange: (() -> Void)?

    private let displayProvider: DisplayProviding
    private let backendBuilder: DisplayBrightnessBackendBuilding
    private let logger = AppLog.displayBrightnessController
    private let shortWriteDelay: TimeInterval

    private var managedDisplays: [CGDirectDisplayID: ManagedDisplay] = [:]
    private var displayOrder: [CGDirectDisplayID] = []
    private var lastErrorMessage: String?
    private var terminateObserver: NSObjectProtocol?

    init(
        displayProvider: DisplayProviding = SystemDisplayService(),
        backendBuilder: DisplayBrightnessBackendBuilding? = nil,
        shortWriteDelay: TimeInterval = 0.05
    ) {
        self.displayProvider = displayProvider
        self.backendBuilder = backendBuilder ?? SystemDisplayBrightnessBackendBuilder(
            displayProvider: displayProvider
        )
        self.shortWriteDelay = shortWriteDelay

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupAll()
            }
        }
    }

    func refresh() {
        let displays = displayProvider.listConnectedDisplays()
        let previousBackends = Dictionary(
            uniqueKeysWithValues: managedDisplays.map { ($0.key, $0.value.backend) }
        )
        let nextBackends = backendBuilder.backends(for: displays, previous: previousBackends)
        let nextDisplayIDs = Set(displays.map(\.id))

        cleanupDisconnectedDisplays(keeping: nextDisplayIDs)

        var nextManagedDisplays: [CGDirectDisplayID: ManagedDisplay] = [:]
        var nextDisplayOrder: [CGDirectDisplayID] = []

        for display in displays {
            guard let backend = nextBackends[display.id] else {
                continue
            }

            let previous = managedDisplays[display.id]
            let brightness = resolvedBrightness(for: display, backend: backend, previous: previous)

            nextManagedDisplays[display.id] = ManagedDisplay(
                display: display,
                backend: backend,
                currentBrightness: previous?.pendingBrightness ?? brightness,
                lastCommittedBrightness: brightness,
                pendingBrightness: previous?.pendingBrightness,
                writeInFlight: previous?.writeInFlight ?? false,
                scheduledFlush: previous?.scheduledFlush
            )
            nextDisplayOrder.append(display.id)
        }

        managedDisplays = nextManagedDisplays
        displayOrder = nextDisplayOrder

        if !nextManagedDisplays.isEmpty {
            lastErrorMessage = nil
        }
    }

    func snapshot() -> DisplayBrightnessSnapshot {
        let displays = displayOrder.compactMap { displayID -> DisplayBrightnessDisplay? in
            guard let managedDisplay = managedDisplays[displayID] else {
                return nil
            }

            return DisplayBrightnessDisplay(
                display: managedDisplay.display,
                brightness: managedDisplay.currentBrightness,
                backendKind: managedDisplay.backend.kind,
                isPendingWrite: managedDisplay.pendingBrightness != nil || managedDisplay.writeInFlight
            )
        }

        return DisplayBrightnessSnapshot(
            displays: displays,
            errorMessage: lastErrorMessage
        )
    }

    func setBrightness(
        _ value: Double,
        for displayID: CGDirectDisplayID,
        phase: PluginPanelAction.SliderPhase
    ) {
        guard var managedDisplay = managedDisplays[displayID] else {
            lastErrorMessage = DisplayBrightnessControllerError.displayUnavailable(
                displayID: displayID
            ).localizedDescription
            return
        }

        let clampedValue = Self.clamp(value)
        managedDisplay.currentBrightness = clampedValue
        managedDisplay.pendingBrightness = clampedValue
        managedDisplay.scheduledFlush?.cancel()
        managedDisplay.scheduledFlush = nil
        lastErrorMessage = nil
        managedDisplays[displayID] = managedDisplay

        let delay = phase == .ended ? 0 : shortWriteDelay
        scheduleWrite(for: displayID, delay: delay)
        onStateChange?()
    }

    private func resolvedBrightness(
        for display: DisplayInfo,
        backend: any DisplayBrightnessBackend,
        previous: ManagedDisplay?
    ) -> Double {
        do {
            return Self.clamp(try backend.readBrightness())
        } catch {
            if let previous {
                return previous.currentBrightness
            }

            logger.error(
                "failed to read brightness for \(display.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return 1
        }
    }

    private func scheduleWrite(for displayID: CGDirectDisplayID, delay: TimeInterval) {
        guard var managedDisplay = managedDisplays[displayID] else {
            return
        }

        let controllerRef = WeakBrightnessControllerRef(self)
        let workItem = Self.makeScheduledWriteWorkItem(
            controllerRef: controllerRef,
            displayID: displayID
        )

        managedDisplay.scheduledFlush = workItem
        managedDisplays[displayID] = managedDisplay

        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func beginWriteIfNeeded(for displayID: CGDirectDisplayID) {
        guard var managedDisplay = managedDisplays[displayID] else {
            return
        }

        guard !managedDisplay.writeInFlight, let targetValue = managedDisplay.pendingBrightness else {
            return
        }

        managedDisplay.writeInFlight = true
        managedDisplay.pendingBrightness = nil
        managedDisplay.scheduledFlush = nil
        let backend = managedDisplay.backend
        let displayName = managedDisplay.display.name
        let controllerRef = WeakBrightnessControllerRef(self)
        managedDisplays[displayID] = managedDisplay

        DispatchQueue.global(qos: .userInitiated).async(
            execute: Self.makeWriteWorkItem(
                controllerRef: controllerRef,
                backend: backend,
                displayID: displayID,
                targetValue: targetValue,
                displayName: displayName
            )
        )
    }

    private func finishWrite(
        for displayID: CGDirectDisplayID,
        targetValue: Double,
        displayName: String,
        result: Result<Void, Error>
    ) {
        guard var managedDisplay = managedDisplays[displayID] else {
            return
        }

        managedDisplay.writeInFlight = false

        switch result {
        case .success:
            managedDisplay.lastCommittedBrightness = targetValue
            if managedDisplay.pendingBrightness == nil {
                managedDisplay.currentBrightness = targetValue
            }
            lastErrorMessage = nil
        case .failure(let error):
            if managedDisplay.pendingBrightness == nil {
                managedDisplay.currentBrightness = managedDisplay.lastCommittedBrightness
            }

            let localizedDescription = error.localizedDescription
            lastErrorMessage = "调节失败：\(localizedDescription)"
            logger.error(
                "write failed for \(displayName, privacy: .public): \(localizedDescription, privacy: .public)"
            )
        }

        managedDisplays[displayID] = managedDisplay
        onStateChange?()

        if managedDisplay.pendingBrightness != nil {
            scheduleWrite(for: displayID, delay: 0)
        }
    }

    private func cleanupDisconnectedDisplays(keeping displayIDs: Set<CGDirectDisplayID>) {
        for (displayID, managedDisplay) in managedDisplays where !displayIDs.contains(displayID) {
            managedDisplay.scheduledFlush?.cancel()
            managedDisplay.backend.cleanup()
        }
    }

    private func cleanupAll() {
        for (_, managedDisplay) in managedDisplays {
            managedDisplay.scheduledFlush?.cancel()
            managedDisplay.backend.cleanup()
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    nonisolated private static func makeScheduledWriteWorkItem(
        controllerRef: WeakBrightnessControllerRef,
        displayID: CGDirectDisplayID
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            Task { @MainActor in
                controllerRef.value?.beginWriteIfNeeded(for: displayID)
            }
        }
    }

    nonisolated private static func makeWriteWorkItem(
        controllerRef: WeakBrightnessControllerRef,
        backend: any DisplayBrightnessBackend,
        displayID: CGDirectDisplayID,
        targetValue: Double,
        displayName: String
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            let result: Result<Void, Error>

            do {
                try backend.writeBrightness(targetValue)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            Task { @MainActor in
                controllerRef.value?.finishWrite(
                    for: displayID,
                    targetValue: targetValue,
                    displayName: displayName,
                    result: result
                )
            }
        }
    }
}
