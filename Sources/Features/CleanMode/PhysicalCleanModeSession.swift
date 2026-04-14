import AppKit
import ApplicationServices
import Foundation
import IOKit.pwr_mgt
import OSLog
import SwiftUI

@MainActor
final class PhysicalCleanModeSession: NSObject, NSWindowDelegate {
    private static let nullAssertionID = IOPMAssertionID(0)

    private struct NotificationObservation {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    enum EndReason {
        case userRequested
        case emergency(String)
    }

    private enum SessionError: LocalizedError {
        case eventTapUnavailable
        case runLoopSourceUnavailable
        case missingScreens
        case overlayWindowCreationFailed
        case idleLockPreventionFailed

        var errorDescription: String? {
            switch self {
            case .eventTapUnavailable:
                return "无法创建输入拦截器，请确认已授予辅助功能权限。"
            case .runLoopSourceUnavailable:
                return "无法初始化输入拦截运行循环。"
            case .missingScreens:
                return "未检测到可用屏幕，无法进入物理清洁模式。"
            case .overlayWindowCreationFailed:
                return "无法创建屏幕覆盖窗口，已取消进入物理清洁模式。"
            case .idleLockPreventionFailed:
                return "无法启用防空闲锁屏保护，已取消进入物理清洁模式。"
            }
        }
    }

    private enum EventTapExitReason {
        case shortcut
        case disabledByTimeout
        case disabledByUserInput
    }

    private enum EventTapInterruptionReason: CustomStringConvertible {
        case disabledByTimeout
        case disabledByUserInput

        var description: String {
            switch self {
            case .disabledByTimeout:
                return "disabledByTimeout"
            case .disabledByUserInput:
                return "disabledByUserInput"
            }
        }

        var exitReason: EventTapExitReason {
            switch self {
            case .disabledByTimeout:
                return .disabledByTimeout
            case .disabledByUserInput:
                return .disabledByUserInput
            }
        }
    }

    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private struct OverlayWatermarkView: View {
        let exitHintText: String

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                Color.clear

                Text(exitHintText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.65), radius: 18, y: 4)
                    .padding(.trailing, 32)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private final class EventTapContext {
        let exitBinding: ShortcutBinding
        private let lock = NSLock()
        private let onExit: (EventTapExitReason) -> Void
        private let onInterruption: (EventTapInterruptionReason, Bool) -> Void
        private var hasTriggeredExit = false
        private var eventTap: CFMachPort?

        init(
            exitBinding: ShortcutBinding,
            onExit: @escaping (EventTapExitReason) -> Void,
            onInterruption: @escaping (EventTapInterruptionReason, Bool) -> Void
        ) {
            self.exitBinding = exitBinding
            self.onExit = onExit
            self.onInterruption = onInterruption
        }

        func requestExit(_ reason: EventTapExitReason) {
            let shouldNotify: Bool

            lock.lock()
            shouldNotify = !hasTriggeredExit
            if shouldNotify {
                hasTriggeredExit = true
            }
            lock.unlock()

            guard shouldNotify else {
                return
            }

            onExit(reason)
        }

        func setEventTap(_ eventTap: CFMachPort) {
            lock.lock()
            self.eventTap = eventTap
            lock.unlock()
        }

        func recoverTap(_ reason: EventTapInterruptionReason) {
            var didRecover = false
            var exitReason: EventTapExitReason?

            lock.lock()

            if hasTriggeredExit {
                lock.unlock()
                return
            }

            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                didRecover = CGEvent.tapIsEnabled(tap: eventTap)

                if !didRecover {
                    hasTriggeredExit = true
                    exitReason = reason.exitReason
                }
            } else {
                hasTriggeredExit = true
                exitReason = reason.exitReason
            }

            lock.unlock()

            onInterruption(reason, didRecover)

            if let exitReason {
                onExit(exitReason)
            }
        }
    }

    let exitBinding: ShortcutBinding

    private let onEnd: (EndReason) -> Void
    private let logger = AppLog.physicalCleanModeSession
    private let sessionIdentifier = String(UUID().uuidString.prefix(8))

    private var overlayWindows: [OverlayWindow] = []
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var eventTapContextPointer: UnsafeMutableRawPointer?
    private var notificationObservers: [NotificationObservation] = []
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var cursorHidden = false
    private var idleSleepAssertionID = IOPMAssertionID(0)
    private var isStopping = false
    private var tapDisableTimestamps: [Date] = []

    private var exitHintText: String {
        "按 \(Self.displayTokens(for: exitBinding).joined(separator: " + ")) 退出清洁模式"
    }

    init(
        exitBinding: ShortcutBinding,
        onEnd: @escaping (EndReason) -> Void
    ) {
        self.exitBinding = exitBinding
        self.onEnd = onEnd
    }

    func start() throws {
        guard eventTap == nil, overlayWindows.isEmpty else {
            return
        }

        if AppLog.isVerboseLoggingEnabled {
            logger.debug("[\(self.sessionIdentifier, privacy: .public)] starting session")
        }

        let tapContext = EventTapContext(
            exitBinding: exitBinding,
            onExit: { [weak self] reason in
                Task { @MainActor in
                    self?.handleEventTapExit(reason)
                }
            },
            onInterruption: { [weak self] reason, didRecover in
                Task { @MainActor in
                    self?.handleEventTapInterruption(reason, didRecover: didRecover)
                }
            }
        )
        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passRetained(tapContext).toOpaque())

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.interceptedEventMask,
            callback: Self.eventTapCallback,
            userInfo: contextPointer
        )

        guard let tap else {
            logger.error("[\(self.sessionIdentifier, privacy: .public)] failed to create event tap")
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
            throw SessionError.eventTapUnavailable
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("[\(self.sessionIdentifier, privacy: .public)] failed to create event tap run loop source")
            CFMachPortInvalidate(tap)
            Unmanaged<EventTapContext>.fromOpaque(contextPointer).release()
            throw SessionError.runLoopSourceUnavailable
        }

        eventTap = tap
        eventTapRunLoopSource = runLoopSource
        eventTapContextPointer = contextPointer
        tapContext.setEventTap(tap)

        CGEvent.tapEnable(tap: tap, enable: false)

        do {
            previousPresentationOptions = NSApp.presentationOptions

            NSApp.activate(ignoringOtherApps: true)
            NSApp.presentationOptions = [
                .hideDock,
                .hideMenuBar,
                .disableProcessSwitching
            ]

            try enableIdleLockPrevention()
            try rebuildOverlayWindows()
            installObservers()
            hideCursor()

            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if AppLog.isVerboseLoggingEnabled {
                logger.debug("[\(self.sessionIdentifier, privacy: .public)] session start completed windows=\(self.overlayWindows.count, privacy: .public)")
            }
        } catch {
            logger.error("[\(self.sessionIdentifier, privacy: .public)] startup failed: \(error.localizedDescription, privacy: .public)")
            tearDown(shouldNotify: false, endReason: .userRequested)
            throw error
        }
    }

    func requestStop(reason: EndReason) {
        tearDown(shouldNotify: true, endReason: reason)
    }

    func requestEmergencyExit(message: String) {
        logger.error("[\(self.sessionIdentifier, privacy: .public)] emergency exit requested message=\(message, privacy: .public)")
        requestStop(reason: .emergency(message))
    }

    func windowWillClose(_ notification: Notification) {
        guard !isStopping else {
            return
        }

        logger.error("[\(self.sessionIdentifier, privacy: .public)] overlay window will close unexpectedly")
        requestEmergencyExit(message: "物理清洁模式覆盖窗口意外关闭，已恢复系统输入。")
    }

    private func installObservers() {
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        notificationObservers.append(
            NotificationObservation(
                center: appCenter,
                token: appCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenParametersChanged()
                }
            }
            )
        )

        notificationObservers.append(
            NotificationObservation(
                center: appCenter,
                token: appCenter.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.requestStop(reason: .userRequested)
                }
                }
            )
        )

        notificationObservers.append(
            NotificationObservation(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleWorkspaceInterruption(
                            message: "当前会话已锁定或切出，已自动退出物理清洁模式。"
                        )
                    }
                }
            )
        )

        notificationObservers.append(
            NotificationObservation(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.screensDidSleepNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleWorkspaceInterruption(
                            message: "屏幕已进入睡眠，已自动退出物理清洁模式。"
                        )
                    }
                }
            )
        )

        notificationObservers.append(
            NotificationObservation(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.willSleepNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleWorkspaceInterruption(
                            message: "系统即将进入睡眠，已自动退出物理清洁模式。"
                        )
                    }
                }
            )
        )
    }

    private func removeObservers() {
        for observer in notificationObservers {
            observer.center.removeObserver(observer.token)
        }

        notificationObservers.removeAll()
    }

    private func handleScreenParametersChanged() {
        guard !isStopping else {
            return
        }

        if AppLog.isVerboseLoggingEnabled {
            logger.debug("[\(self.sessionIdentifier, privacy: .public)] screen parameters changed, rebuilding overlay windows")
        }

        do {
            try rebuildOverlayWindows()
        } catch {
            requestEmergencyExit(message: error.localizedDescription)
        }
    }

    private func handleWorkspaceInterruption(message: String) {
        guard !isStopping else {
            return
        }

        requestEmergencyExit(message: message)
    }

    private func rebuildOverlayWindows() throws {
        guard !NSScreen.screens.isEmpty else {
            throw SessionError.missingScreens
        }

        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        let windows = try createOverlayWindows(level: level)

        guard let focusWindow = windows.first else {
            throw SessionError.overlayWindowCreationFailed
        }

        focusWindow.makeKeyAndOrderFront(nil)

        let previousWindows = overlayWindows
        overlayWindows = windows
        closeOverlayWindows(previousWindows)
    }

    private func createOverlayWindows(level: NSWindow.Level) throws -> [OverlayWindow] {
        var windows: [OverlayWindow] = []

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.delegate = self
            window.level = level
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: true)
            window.contentView = NSHostingView(
                rootView: OverlayWatermarkView(exitHintText: exitHintText)
            )
            window.orderFrontRegardless()
            windows.append(window)
        }

        guard !windows.isEmpty else {
            throw SessionError.overlayWindowCreationFailed
        }

        return windows
    }

    private func enableIdleLockPrevention() throws {
        guard idleSleepAssertionID == Self.nullAssertionID else {
            return
        }

        var assertionID = Self.nullAssertionID
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacTools Physical Clean Mode" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            logger.error(
                "[\(self.sessionIdentifier, privacy: .public)] failed to create idle-sleep assertion result=\(result, privacy: .public)"
            )
            throw SessionError.idleLockPreventionFailed
        }

        idleSleepAssertionID = assertionID
    }

    private func releaseIdleLockPrevention() {
        guard idleSleepAssertionID != Self.nullAssertionID else {
            return
        }

        let assertionID = idleSleepAssertionID
        idleSleepAssertionID = Self.nullAssertionID
        let result = IOPMAssertionRelease(assertionID)

        if result != kIOReturnSuccess {
            logger.error(
                "[\(self.sessionIdentifier, privacy: .public)] failed to release idle-sleep assertion result=\(result, privacy: .public)"
            )
        }
    }

    private func closeOverlayWindows(_ windows: [OverlayWindow]? = nil) {
        let windowsToClose = windows ?? overlayWindows

        if windows == nil {
            overlayWindows.removeAll()
        }

        for window in windowsToClose {
            window.delegate = nil
            window.close()
        }
    }

    private func hideCursor() {
        guard !cursorHidden else {
            return
        }

        NSCursor.hide()
        cursorHidden = true
    }

    private func showCursorIfNeeded() {
        guard cursorHidden else {
            return
        }

        NSCursor.unhide()
        cursorHidden = false
    }

    private func tearDown(shouldNotify: Bool, endReason: EndReason) {
        guard !isStopping else {
            return
        }

        if case .emergency = endReason {
            logger.error("[\(self.sessionIdentifier, privacy: .public)] tearing down session reason=\(String(describing: endReason), privacy: .public)")
        } else if AppLog.isVerboseLoggingEnabled {
            logger.debug("[\(self.sessionIdentifier, privacy: .public)] tearing down session reason=\(String(describing: endReason), privacy: .public)")
        }

        isStopping = true

        removeObservers()
        closeOverlayWindows()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, CFRunLoopMode.commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        eventTap = nil
        eventTapRunLoopSource = nil

        if let eventTapContextPointer {
            Unmanaged<EventTapContext>.fromOpaque(eventTapContextPointer).release()
            self.eventTapContextPointer = nil
        }

        showCursorIfNeeded()
        releaseIdleLockPrevention()

        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }

        isStopping = false

        if shouldNotify {
            onEnd(endReason)
        }
    }

    private func handleEventTapExit(_ reason: EventTapExitReason) {
        switch reason {
        case .shortcut:
            if AppLog.isVerboseLoggingEnabled {
                logger.debug("[\(self.sessionIdentifier, privacy: .public)] event tap requested exit reason=shortcut")
            }
            requestStop(reason: .userRequested)
        case .disabledByTimeout:
            logger.error("[\(self.sessionIdentifier, privacy: .public)] event tap could not recover from timeout interruption")
            requestEmergencyExit(message: "输入拦截重启失败，已自动退出物理清洁模式。")
        case .disabledByUserInput:
            logger.error("[\(self.sessionIdentifier, privacy: .public)] event tap could not recover from user-input interruption")
            requestEmergencyExit(message: "输入拦截被系统停用且无法恢复，已自动退出物理清洁模式。")
        }
    }

    private func handleEventTapInterruption(
        _ reason: EventTapInterruptionReason,
        didRecover: Bool
    ) {
        if AppLog.isVerboseLoggingEnabled {
            logger.debug("[\(self.sessionIdentifier, privacy: .public)] event tap interruption reason=\(reason.description, privacy: .public) recovered=\(didRecover, privacy: .public)")
        }

        guard didRecover else {
            return
        }

        let now = Date()
        tapDisableTimestamps.append(now)
        tapDisableTimestamps.removeAll { now.timeIntervalSince($0) > 2 }

        if tapDisableTimestamps.count >= 3 {
            requestEmergencyExit(message: "输入拦截被系统连续停用，已自动退出物理清洁模式。")
        }
    }

    private nonisolated static let interceptedEventMask: CGEventMask = {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged,
            .scrollWheel
        ]

        return eventTypes.reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | (CGEventMask(1) << UInt64(eventType.rawValue))
        }
    }()

    private static func displayTokens(for binding: ShortcutBinding) -> [String] {
        var tokens: [String] = []

        if binding.modifiers.contains(.control) {
            tokens.append("⌃")
        }

        if binding.modifiers.contains(.option) {
            tokens.append("⌥")
        }

        if binding.modifiers.contains(.shift) {
            tokens.append("⇧")
        }

        if binding.modifiers.contains(.command) {
            tokens.append("⌘")
        }

        tokens.append(ShortcutFormatter.keyDisplayName(for: binding.keyCode))
        return tokens
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let context = Unmanaged<EventTapContext>.fromOpaque(userInfo).takeUnretainedValue()

        switch type {
        case .tapDisabledByTimeout:
            context.recoverTap(.disabledByTimeout)
            return Unmanaged.passUnretained(event)
        case .tapDisabledByUserInput:
            context.recoverTap(.disabledByUserInput)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = ShortcutModifiers.from(event.flags)

            if keyCode == context.exitBinding.keyCode, modifiers == context.exitBinding.modifiers {
                context.requestExit(.shortcut)
            }

            return nil
        case .keyUp,
             .flagsChanged,
             .mouseMoved,
             .leftMouseDown,
             .leftMouseUp,
             .leftMouseDragged,
             .rightMouseDown,
             .rightMouseUp,
             .rightMouseDragged,
             .otherMouseDown,
             .otherMouseUp,
             .otherMouseDragged,
             .scrollWheel:
            return nil
        default:
            return nil
        }
    }
}
