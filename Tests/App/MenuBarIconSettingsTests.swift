import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacTools

@MainActor
final class MenuBarIconSettingsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var rootDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "MenuBarIconSettingsTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarIconSettingsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        try super.tearDownWithError()
    }

    func testImportPersistsCustomIconAndRecentItem() throws {
        let sourceURL = try makeImageFile(name: "status-icon.png", color: .systemBlue)
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importIcon(from: sourceURL, for: .light)
        settings.renderMode = .original

        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertEqual(settings.recentItems.count, 1)
        XCTAssertEqual(settings.recentItems.first?.displayName, "status-icon")

        let reloadedSettings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )
        let payload = reloadedSettings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertTrue(reloadedSettings.hasCustomIcon)
        XCTAssertFalse(payload.isTemplate)
        XCTAssertEqual(payload.image.size, NSSize(width: 18, height: 18))
    }

    func testDarkAppearanceFallsBackToLightCustomIcon() throws {
        let sourceURL = try makeImageFile(name: "shared.png", color: .systemRed)
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importIcon(from: sourceURL, for: .light)

        let payload = settings.imagePayload(for: NSAppearance(named: .darkAqua))

        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertEqual(payload.image.size, NSSize(width: 18, height: 18))
    }

    func testResetToDefaultClearsCustomSelectionButKeepsRecents() throws {
        let sourceURL = try makeImageFile(name: "reset.png", color: .systemGreen)
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importIcon(from: sourceURL, for: .light)
        settings.resetToDefault()

        XCTAssertFalse(settings.hasCustomIcon)
        XCTAssertEqual(settings.recentItems.count, 1)
        XCTAssertTrue(settings.imagePayload(for: NSAppearance(named: .aqua)).isTemplate)
    }

    func testAdjustmentIsClamped() {
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.setAdjustment(
            MenuBarIconAdjustment(scale: 9, offsetX: -20, offsetY: 20),
            for: .light
        )

        XCTAssertEqual(settings.adjustment(for: .light), MenuBarIconAdjustment(scale: 2, offsetX: -8, offsetY: 8))
    }

    func testAnimationSpeedSettingsPersistAndClampManualMultiplier() {
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.animationSpeedMode = .adaptiveSystemLoad
        settings.manualAnimationSpeedMultiplier = 9

        let reloadedSettings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        XCTAssertEqual(reloadedSettings.animationSpeedMode, .adaptiveSystemLoad)
        XCTAssertEqual(
            reloadedSettings.manualAnimationSpeedMultiplier,
            MenuBarIconAnimationSpeedPolicy.maximumMultiplier
        )
    }

    func testPersistedChangesIncrementSettingsRevisionAfterStateChanges() throws {
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )
        let initialRevision = settings.settingsRevision

        settings.manualAnimationSpeedMultiplier = 1.4

        XCTAssertGreaterThan(settings.settingsRevision, initialRevision)
    }

    func testAdaptiveAnimationSpeedUsesAvailableSystemLoad() {
        let lowLoadMultiplier = MenuBarIconAnimationSpeedPolicy.multiplier(
            mode: .adaptiveSystemLoad,
            manualMultiplier: 1,
            systemLoad: MenuBarIconAnimationSystemLoad(cpuUsage: 0.1, gpuUsage: nil, memoryUsage: 0.2)
        )
        let highLoadMultiplier = MenuBarIconAnimationSpeedPolicy.multiplier(
            mode: .adaptiveSystemLoad,
            manualMultiplier: 1,
            systemLoad: MenuBarIconAnimationSystemLoad(cpuUsage: 0.9, gpuUsage: 0.8, memoryUsage: 0.7)
        )

        XCTAssertGreaterThan(highLoadMultiplier, lowLoadMultiplier)
        XCTAssertLessThanOrEqual(highLoadMultiplier, MenuBarIconAnimationSpeedPolicy.maximumMultiplier)
    }

    func testImportAnimatedGIFStoresLoopFrames() throws {
        let sourceURL = try makeAnimatedGIFFile(name: "pulse.gif")
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importAnimation(from: sourceURL, for: .light)
        let payload = settings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertEqual(settings.recentItems.first?.mediaKind, .animation)
        XCTAssertTrue(payload.isAnimated)
        XCTAssertLessThanOrEqual(payload.animationFrames.count, MenuBarIconProcessing.maxAnimationFrames)
        XCTAssertEqual(payload.frameDuration, 1.0 / MenuBarIconProcessing.animationFramesPerSecond)
    }

    func testImportMP4StoresLoopFrames() throws {
        let sourceURL = try makeMP4File(name: "runner.mp4")
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importAnimation(from: sourceURL, for: .light)
        let payload = settings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertEqual(settings.recentItems.first?.mediaKind, .animation)
        XCTAssertTrue(payload.isAnimated)
        XCTAssertGreaterThan(payload.animationFrames.count, 1)
    }

    func testLongButSmallAnimatedGIFIsAcceptedAndDownsampled() throws {
        let sourceURL = try makeAnimatedGIFFile(name: "slow.gif", frameDelay: 2.5)
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importAnimation(from: sourceURL, for: .light)
        let payload = settings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(payload.isAnimated)
        XCTAssertLessThanOrEqual(payload.animationFrames.count, MenuBarIconProcessing.maxAnimationFrames)
    }

    func testBuiltInRunCatAnimationCanBeSelected() throws {
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )
        let animation = try XCTUnwrap(settings.builtInAnimations.first { $0.id == "runcat" })

        settings.useBuiltInAnimation(animation, for: .light)
        let payload = settings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertEqual(settings.recentItems.first?.displayName, "RunCat")
        XCTAssertEqual(payload.animationFrames.count, 5)
        XCTAssertTrue(payload.isAnimated)
    }

    func testBuiltInRunningLeftAnimationCanBeSelected() throws {
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )
        let animation = try XCTUnwrap(settings.builtInAnimations.first { $0.id == "running-left" })

        settings.useBuiltInAnimation(animation, for: .light)
        let payload = settings.imagePayload(for: NSAppearance(named: .aqua))

        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(settings.hasCustomIcon)
        XCTAssertEqual(settings.recentItems.first?.displayName, "奔跑狗狗")
        XCTAssertEqual(payload.animationFrames.count, 52)
        XCTAssertEqual(payload.frameDuration, 1.0 / 12.0)
        XCTAssertTrue(payload.isAnimated)
    }

    func testOversizedAnimationIsRejectedBeforeDecoding() throws {
        let url = rootDirectory.appendingPathComponent("too-large.gif")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0, count: MenuBarIconProcessing.maxAnimationFileSize + 1).write(to: url)
        let settings = MenuBarIconSettings(
            userDefaults: userDefaults,
            rootDirectory: rootDirectory
        )

        settings.importAnimation(from: url, for: .light)

        XCTAssertFalse(settings.hasCustomIcon)
        XCTAssertEqual(settings.lastErrorMessage, MenuBarIconImportError.animationTooLarge.userMessage)
    }

    func testBackgroundRemoverMakesCornerColoredPixelsTransparent() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 16, height: 16)).fill()
        image.unlockFocus()

        let output = try XCTUnwrap(
            MenuBarIconBackgroundRemover.removingBackground(
                from: image,
                options: .default
            )
        )
        let cgImage = try XCTUnwrap(cgImage(from: output))
        let pixel = try XCTUnwrap(pixelRGBA(in: cgImage, x: 0, y: 0))

        XCTAssertLessThan(pixel.alpha, 32)
    }

    private func makeImageFile(name: String, color: NSColor) throws -> URL {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 48, height: 48)).fill()
        image.unlockFocus()

        let url = rootDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(MenuBarIconProcessing.pngData(from: image))
        try data.write(to: url)
        return url
    }

    private func makeAnimatedGIFFile(name: String, frameDelay: Double = 0.12) throws -> URL {
        let url = rootDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            3,
            nil
        ) else {
            XCTFail("Could not create GIF destination")
            return url
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary
        )

        for color in [NSColor.systemRed, .systemGreen, .systemBlue] {
            let image = NSImage(size: NSSize(width: 32, height: 32))
            image.lockFocus()
            color.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
            image.unlockFocus()

            guard let cgImage = cgImage(from: image) else {
                XCTFail("Could not make GIF frame")
                return url
            }

            CGImageDestinationAddImage(
                destination,
                cgImage,
                [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frameDelay
                    ]
                ] as CFDictionary
            )
        }

        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeMP4File(name: String) throws -> URL {
        let url = rootDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)

        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for (index, color) in [NSColor.systemRed, .systemGreen, .systemBlue, .systemOrange].enumerated() {
            let buffer = try XCTUnwrap(makePixelBuffer(color: color))
            while !input.isReadyForMoreMediaData {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 6)))
        }

        input.markAsFinished()
        let finished = expectation(description: "MP4 writer finished")
        writer.finishWriting {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func makePixelBuffer(color: NSColor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        guard result == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: baseAddress,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            return nil
        }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return pixelBuffer
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private func pixelRGBA(in image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: CGFloat(-x), y: CGFloat(y - image.height + 1))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (red: pixel[0], green: pixel[1], blue: pixel[2], alpha: pixel[3])
    }
}
