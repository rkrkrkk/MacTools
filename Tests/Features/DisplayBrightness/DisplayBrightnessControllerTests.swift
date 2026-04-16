import XCTest
@testable import MacTools

@MainActor
final class DisplayBrightnessControllerTests: XCTestCase {
    func testRefreshKeepsOnlyDisplaysWithAvailableBackends() {
        let builtIn = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let projector = makeTestDisplay(id: 2, name: "Projector")
        let provider = StubDisplayProvider(displays: [builtIn, projector])
        let builtInBackend = TestBrightnessBackend(
            kind: .appleNative,
            display: builtIn,
            brightness: 0.64
        )
        let builder = StubBrightnessBackendBuilder { displays, _ in
            XCTAssertEqual(displays.map(\.id), [1, 2])
            return [1: builtInBackend]
        }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        let snapshot = controller.snapshot()

        XCTAssertEqual(snapshot.displays.map(\.id), [1])
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.64)
        XCTAssertNil(snapshot.errorMessage)
    }

    func testChangedPhaseUpdatesSnapshotOptimisticallyBeforeWriteCompletes() async {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.4)
        backend.writeDelay = 0.05
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.8, for: display.id, phase: .changed)

        let optimisticSnapshot = controller.snapshot()
        XCTAssertEqual(optimisticSnapshot.displays.first?.brightness, 0.8)
        XCTAssertEqual(optimisticSnapshot.displays.first?.isPendingWrite, true)

        await waitUntil {
            controller.snapshot().displays.first?.isPendingWrite == false
        }

        let committedSnapshot = controller.snapshot()
        XCTAssertEqual(committedSnapshot.displays.first?.brightness, 0.8)
        XCTAssertEqual(backend.recordedWrites, [0.8])
    }

    func testEndedPhaseFailureRollsBackToLastCommittedBrightness() async {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.6)
        backend.enqueueWriteError(DisplayBrightnessControllerError.failed(message: "DDC 写入失败"))
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.25, for: display.id, phase: .ended)

        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.25)

        await waitUntil {
            controller.snapshot().errorMessage != nil
        }

        let snapshot = controller.snapshot()
        XCTAssertEqual(snapshot.displays.first?.brightness, 0.6)
        XCTAssertEqual(snapshot.errorMessage, "调节失败：DDC 写入失败")
    }

    func testInFlightWritesRemainSerialAndFlushLatestValue() async {
        let display = makeTestDisplay(id: 1, name: "Studio Display")
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .ddc, display: display, brightness: 0.5)
        backend.blockFirstWrite = true
        let builder = StubBrightnessBackendBuilder { _, _ in [display.id: backend] }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        controller.setBrightness(0.2, for: display.id, phase: .ended)

        await waitUntil {
            backend.writeCount == 1
        }

        controller.setBrightness(0.85, for: display.id, phase: .ended)
        backend.allowFirstWriteToFinish.signal()

        await waitUntil {
            backend.writeCount == 2 && controller.snapshot().displays.first?.isPendingWrite == false
        }

        XCTAssertEqual(backend.recordedWrites, [0.2, 0.85])
        XCTAssertEqual(backend.maxConcurrentWrites, 1)
        XCTAssertEqual(controller.snapshot().displays.first?.brightness, 0.85)
    }

    func testRefreshCleansUpDisconnectedDisplays() {
        let display = makeTestDisplay(id: 1, name: "Built-in Display", isBuiltin: true, isMain: true)
        let provider = StubDisplayProvider(displays: [display])
        let backend = TestBrightnessBackend(kind: .appleNative, display: display, brightness: 0.6)
        let builder = StubBrightnessBackendBuilder { displays, previous in
            guard let activeDisplay = displays.first else {
                return [:]
            }

            if let existing = previous[activeDisplay.id] {
                return [activeDisplay.id: existing]
            }

            return [activeDisplay.id: backend]
        }

        let controller = DisplayBrightnessController(
            displayProvider: provider,
            backendBuilder: builder,
            shortWriteDelay: 0.01
        )
        controller.refresh()

        provider.displays = []
        controller.refresh()

        XCTAssertEqual(backend.cleanupCount, 1)
        XCTAssertTrue(controller.snapshot().displays.isEmpty)
    }

    func testDDCBackendMapsPercentageToRawValueUsingDisplayMaximum() throws {
        let display = makeTestDisplay(id: 8, name: "LG UltraFine")
        let transport = MockDDCTransport(
            initialBrightness: DDCBrightnessValue(current: 40, maximum: 80)
        )

        let backend = try XCTUnwrap(
            DDCBrightnessBackend(display: display, transport: transport)
        )

        XCTAssertEqual(try backend.readBrightness(), 0.5, accuracy: 0.0001)

        try backend.writeBrightness(0.25)

        XCTAssertEqual(transport.recordedWrites, [20])
    }

    func testBackendBuilderPrefersFirstAvailableBackendInConfiguredOrder() {
        let display = makeTestDisplay(id: 11, name: "External Display")
        var attempts: [String] = []
        let builder = SystemDisplayBrightnessBackendBuilder(
            displayProvider: StubDisplayProvider(displays: [display]),
            resolveArm64Services: { _ in [:] },
            appleFactory: { currentDisplay in
                attempts.append("apple:\(currentDisplay.id)")
                return nil
            },
            ddcFactory: { currentDisplay, _ in
                attempts.append("ddc:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .ddc, display: currentDisplay, brightness: 0.7)
            },
            gammaFactory: { currentDisplay in
                attempts.append("gamma:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .gamma, display: currentDisplay, brightness: 0.7)
            },
            shadeFactory: { currentDisplay in
                attempts.append("shade:\(currentDisplay.id)")
                return TestBrightnessBackend(kind: .shade, display: currentDisplay, brightness: 0.7)
            }
        )

        let backends = builder.backends(for: [display], previous: [:])

        XCTAssertEqual(attempts, ["apple:11", "ddc:11"])
        XCTAssertEqual(backends[display.id]?.kind, .ddc)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Condition was not satisfied before timeout", file: file, line: line)
    }
}

private final class MockDDCTransport: DDCBrightnessTransport {
    private var brightness: DDCBrightnessValue
    private(set) var recordedWrites: [UInt16] = []

    init(initialBrightness: DDCBrightnessValue) {
        self.brightness = initialBrightness
    }

    func readBrightness() throws -> DDCBrightnessValue {
        brightness
    }

    func writeBrightness(_ value: UInt16) throws {
        recordedWrites.append(value)
    }
}
