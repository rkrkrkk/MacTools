import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import IOKit.i2c

private enum DDCBrightnessControl {
    static let brightness: UInt8 = 0x10
    static let hostAddress: UInt8 = 0x51
    static let displayAddress: UInt8 = 0x6E
    static let displayReplyAddress: UInt8 = 0x6F
    static let arm64DisplayAddress7Bit: UInt8 = 0x37
}

struct DDCBrightnessValue {
    let current: UInt16
    let maximum: UInt16
}

protocol DDCBrightnessTransport {
    func readBrightness() throws -> DDCBrightnessValue
    func writeBrightness(_ value: UInt16) throws
}

final class IntelDDCTransport: DDCBrightnessTransport, @unchecked Sendable {
    private let display: DisplayInfo
    private let framebuffer: io_service_t
    private let replyTransactionType: IOOptionBits

    init?(display: DisplayInfo) {
        guard let framebuffer = Self.framebufferPort(for: display.id) else {
            return nil
        }

        guard let replyTransactionType = Self.supportedReplyTransactionType() else {
            IOObjectRelease(framebuffer)
            return nil
        }

        self.display = display
        self.framebuffer = framebuffer
        self.replyTransactionType = replyTransactionType
    }

    deinit {
        IOObjectRelease(framebuffer)
    }

    func readBrightness() throws -> DDCBrightnessValue {
        var command = [
            DDCBrightnessControl.hostAddress,
            0x82,
            0x01,
            DDCBrightnessControl.brightness
        ]
        command.append(Self.checksum(seed: DDCBrightnessControl.displayAddress, bytes: command))
        var reply = Array(repeating: UInt8.zero, count: 11)

        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = UInt32(DDCBrightnessControl.displayAddress)
        request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        request.sendBytes = UInt32(command.count)
        request.sendBuffer = command.withUnsafeBufferPointer {
            vm_address_t(bitPattern: $0.baseAddress)
        }
        request.minReplyDelay = 10
        request.replyAddress = UInt32(DDCBrightnessControl.displayReplyAddress)
        request.replySubAddress = DDCBrightnessControl.hostAddress
        request.replyTransactionType = replyTransactionType
        request.replyBytes = UInt32(reply.count)
        request.replyBuffer = reply.withUnsafeMutableBufferPointer {
            vm_address_t(bitPattern: $0.baseAddress)
        }

        guard Self.send(request: &request, to: framebuffer) else {
            throw DisplayBrightnessControllerError.i2cUnavailable(displayName: display.name)
        }

        return try Self.parseReply(reply, displayName: display.name)
    }

    func writeBrightness(_ value: UInt16) throws {
        var command = [
            DDCBrightnessControl.hostAddress,
            0x84,
            0x03,
            DDCBrightnessControl.brightness,
            UInt8(value >> 8),
            UInt8(value & 0xFF)
        ]
        command.append(Self.checksum(seed: DDCBrightnessControl.displayAddress, bytes: command))

        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = UInt32(DDCBrightnessControl.displayAddress)
        request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        request.sendBytes = UInt32(command.count)
        request.sendBuffer = command.withUnsafeBufferPointer {
            vm_address_t(bitPattern: $0.baseAddress)
        }
        request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
        request.replyBytes = 0

        guard Self.send(request: &request, to: framebuffer) else {
            throw DisplayBrightnessControllerError.failed(message: "\(display.name) DDC 写入失败")
        }
    }

    static func parseReply(
        _ reply: [UInt8],
        displayName: String
    ) throws -> DDCBrightnessValue {
        guard reply.count >= 10 else {
            throw DisplayBrightnessControllerError.unsupportedReply(displayName: displayName)
        }

        let checksum = checksum(seed: 0x50, bytes: Array(reply.dropLast()))
        guard checksum == reply.last else {
            throw DisplayBrightnessControllerError.unsupportedReply(displayName: displayName)
        }

        guard reply[2] == 0x02, reply[3] == 0x00 else {
            throw DisplayBrightnessControllerError.unsupportedReply(displayName: displayName)
        }

        return DDCBrightnessValue(
            current: UInt16(reply[8]) << 8 | UInt16(reply[9]),
            maximum: UInt16(reply[6]) << 8 | UInt16(reply[7])
        )
    }

    private static func checksum(seed: UInt8, bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    private static func send(request: inout IOI2CRequest, to framebuffer: io_service_t) -> Bool {
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS else {
            return false
        }

        for bus in 0..<busCount {
            var interface = io_service_t()
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else {
                continue
            }

            defer {
                IOObjectRelease(interface)
            }

            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connect) == KERN_SUCCESS, let connect else {
                continue
            }

            defer {
                IOI2CInterfaceClose(connect, 0)
            }

            if IOI2CSendRequest(connect, 0, &request) == KERN_SUCCESS, request.result == KERN_SUCCESS {
                return true
            }
        }

        return false
    }

    private static func supportedReplyTransactionType() -> IOOptionBits? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceNameMatching("IOFramebufferI2CInterface"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any],
            let types = dictionary[kIOI2CTransactionTypesKey] as? UInt64
            else {
                continue
            }

            if (1 << kIOI2CDDCciReplyTransactionType) & types != 0 {
                return IOOptionBits(kIOI2CDDCciReplyTransactionType)
            }

            if (1 << kIOI2CSimpleTransactionType) & types != 0 {
                return IOOptionBits(kIOI2CSimpleTransactionType)
            }
        }

        return nil
    }

    private static func framebufferPort(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let vendorID = CGDisplayVendorNumber(displayID)
            let modelID = CGDisplayModelNumber(displayID)
            let serialNumber = CGDisplaySerialNumber(displayID)

            let infoDictionary = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary

            let matchesVendor = (infoDictionary[kDisplayVendorID] as? UInt32) == vendorID
            let matchesModel = (infoDictionary[kDisplayProductID] as? UInt32) == modelID
            let displaySerial = infoDictionary[kDisplaySerialNumber] as? UInt32
            let matchesSerial = serialNumber == 0 || displaySerial == serialNumber

            if matchesVendor && matchesModel && matchesSerial {
                return service
            }

            IOObjectRelease(service)
        }

        return nil
    }
}

final class Arm64DDCTransport: DDCBrightnessTransport, @unchecked Sendable {
    private let display: DisplayInfo
    private let service: CFTypeRef

    init?(display: DisplayInfo, service matchedService: CFTypeRef?) {
        guard
            let service = matchedService ?? PrivateDDCBridge.createService(for: display.id)
        else {
            return nil
        }

        self.display = display
        self.service = service
    }

    func readBrightness() throws -> DDCBrightnessValue {
        var payload = [DDCBrightnessControl.brightness]
        var reply = Array(repeating: UInt8.zero, count: 11)
        try performCommunication(send: &payload, reply: &reply)
        return try IntelDDCTransport.parseReply(reply, displayName: display.name)
    }

    func writeBrightness(_ value: UInt16) throws {
        var payload = [
            DDCBrightnessControl.brightness,
            UInt8(value >> 8),
            UInt8(value & 0xFF)
        ]
        var reply: [UInt8] = []
        try performCommunication(send: &payload, reply: &reply)
    }

    private func performCommunication(send: inout [UInt8], reply: inout [UInt8]) throws {
        var packet = [UInt8(0x80 | UInt8(send.count + 1)), UInt8(send.count)] + send + [0]
        let seed = send.count == 1
            ? DDCBrightnessControl.arm64DisplayAddress7Bit << 1
            : (DDCBrightnessControl.arm64DisplayAddress7Bit << 1) ^ DDCBrightnessControl.hostAddress
        packet[packet.count - 1] = packet.dropLast().reduce(seed, ^)

        guard PrivateDDCBridge.writeI2C(
            service: service,
            address: UInt32(DDCBrightnessControl.arm64DisplayAddress7Bit),
            dataAddress: UInt32(DDCBrightnessControl.hostAddress),
            bytes: &packet
        ) == KERN_SUCCESS else {
            throw DisplayBrightnessControllerError.i2cUnavailable(displayName: display.name)
        }

        guard !reply.isEmpty else {
            return
        }

        usleep(50_000)

        guard PrivateDDCBridge.readI2C(
            service: service,
            address: UInt32(DDCBrightnessControl.arm64DisplayAddress7Bit),
            dataAddress: 0,
            bytes: &reply
        ) == KERN_SUCCESS else {
            throw DisplayBrightnessControllerError.i2cUnavailable(displayName: display.name)
        }
    }
}

enum Arm64DDCServiceMatcher {
    private struct CandidateService {
        let service: CFTypeRef
        let name: String?
        let vendorNumber: UInt32?
        let serialNumber: UInt32?
        let location: String?
    }

    static func resolveServices(for displays: [DisplayInfo]) -> [CGDirectDisplayID: CFTypeRef] {
        var candidates = discoverCandidates()
        var matches: [CGDirectDisplayID: CFTypeRef] = [:]

        for display in displays where !display.isBuiltin {
            guard let matchIndex = bestMatchIndex(for: display, candidates: candidates) else {
                continue
            }

            let candidate = candidates.remove(at: matchIndex)
            matches[display.id] = candidate.service
        }

        return matches
    }

    private static func discoverCandidates() -> [CandidateService] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceNameMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }

        defer {
            IOObjectRelease(iterator)
        }

        var result: [CandidateService] = []

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            guard let avService = PrivateDDCBridge.createService(with: service) else {
                continue
            }

            let location = searchedProperty(
                key: "Location",
                service: service
            ) as? String
            guard location?.localizedCaseInsensitiveContains("external") ?? true else {
                continue
            }

            let attributes = searchedProperty(
                key: "DisplayAttributes",
                service: service
            ) as? [String: Any]
            let productAttributes = attributes?["ProductAttributes"] as? [String: Any]

            result.append(
                CandidateService(
                    service: avService,
                    name: productAttributes?["ProductName"] as? String,
                    vendorNumber: productAttributes?["ManufacturerID"] as? UInt32,
                    serialNumber: productAttributes?["SerialNumber"] as? UInt32,
                    location: location
                )
            )
        }

        return result
    }

    private static func bestMatchIndex(
        for display: DisplayInfo,
        candidates: [CandidateService]
    ) -> Int? {
        var bestIndex: Int?
        var bestScore = Int.min

        for index in candidates.indices {
            let candidate = candidates[index]
            var score = 0

            if let serialNumber = display.serialNumber, serialNumber != 0, serialNumber == candidate.serialNumber {
                score += 10
            }

            if display.vendorNumber == candidate.vendorNumber {
                score += 3
            }

            if let name = candidate.name, name.localizedCaseInsensitiveCompare(display.name) == .orderedSame {
                score += 2
            }

            if let location = candidate.location, location.localizedCaseInsensitiveContains("external") {
                score += 1
            }

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestScore > 0 ? bestIndex : nil
    }

    private static func searchedProperty(key: String, service: io_service_t) -> AnyObject? {
        IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
    }
}

private enum PrivateDDCBridge {
    private typealias CreateWithServiceFunction = @convention(c) (
        CFAllocator?,
        io_service_t
    ) -> Unmanaged<CFTypeRef>?
    private typealias ReadI2CFunction = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> kern_return_t
    private typealias WriteI2CFunction = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> kern_return_t
    private typealias CGSServiceFunction = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<io_service_t>
    ) -> Void

    private static let createWithService: CreateWithServiceFunction? = loadSymbol("IOAVServiceCreateWithService")
    private static let read: ReadI2CFunction? = loadSymbol("IOAVServiceReadI2C")
    private static let write: WriteI2CFunction? = loadSymbol("IOAVServiceWriteI2C")
    private static let cgsServiceForDisplay: CGSServiceFunction? = loadSymbol("CGSServiceForDisplayNumber")

    static func createService(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        guard let cgsServiceForDisplay, let createWithService else {
            return nil
        }

        var service = io_service_t()
        cgsServiceForDisplay(displayID, &service)
        guard service != 0 else {
            return nil
        }

        return createWithService(kCFAllocatorDefault, service)?.takeRetainedValue()
    }

    static func createService(with service: io_service_t) -> CFTypeRef? {
        createWithService?(kCFAllocatorDefault, service)?.takeRetainedValue()
    }

    static func readI2C(
        service: CFTypeRef,
        address: UInt32,
        dataAddress: UInt32,
        bytes: inout [UInt8]
    ) -> kern_return_t {
        guard let read else {
            return kIOReturnUnsupported
        }

        return bytes.withUnsafeMutableBytes { buffer in
            read(service, address, dataAddress, buffer.baseAddress, UInt32(buffer.count))
        }
    }

    static func writeI2C(
        service: CFTypeRef,
        address: UInt32,
        dataAddress: UInt32,
        bytes: inout [UInt8]
    ) -> kern_return_t {
        guard let write else {
            return kIOReturnUnsupported
        }

        return bytes.withUnsafeMutableBytes { buffer in
            write(service, address, dataAddress, buffer.baseAddress, UInt32(buffer.count))
        }
    }

    private static func loadSymbol<T>(_ symbol: String) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else {
            return nil
        }

        return unsafeBitCast(pointer, to: T.self)
    }
}
