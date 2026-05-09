import Darwin
import Foundation
import IOKit

final class MenuBarIconAnimationLoadMonitor {
    private var previousCPUTicks: CPUTicks?

    func sample() -> MenuBarIconAnimationSystemLoad {
        MenuBarIconAnimationSystemLoad(
            cpuUsage: sampleCPUUsage(),
            gpuUsage: Self.sampleGPUUsage(),
            memoryUsage: Self.sampleMemoryUsage()
        )
    }

    private func sampleCPUUsage() -> Double? {
        guard let currentTicks = Self.readCPUTicks() else {
            previousCPUTicks = nil
            return nil
        }

        defer { previousCPUTicks = currentTicks }
        guard let previousCPUTicks else {
            return nil
        }

        let user = currentTicks.user.saturatingDelta(from: previousCPUTicks.user)
        let system = currentTicks.system.saturatingDelta(from: previousCPUTicks.system)
        let nice = currentTicks.nice.saturatingDelta(from: previousCPUTicks.nice)
        let idle = currentTicks.idle.saturatingDelta(from: previousCPUTicks.idle)
        let total = user + system + nice + idle

        guard total > 0 else {
            return nil
        }

        return min(max(Double(user + system + nice) / Double(total), 0), 1)
    }

    private static func readCPUTicks() -> CPUTicks? {
        let count = MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: count) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func sampleMemoryUsage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let pageSize = Double(memoryPageSize())
        let active = Double(stats.active_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let rawUsed = active + inactive + speculative + wired + compressed - purgeable - external
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        guard total > 0 else {
            return nil
        }

        return min(max(rawUsed / total, 0), 1)
    }

    private static func memoryPageSize() -> vm_size_t {
        var pageSize: vm_size_t = 0
        let result = host_page_size(mach_host_self(), &pageSize)
        guard result == KERN_SUCCESS, pageSize > 0 else {
            return 16_384
        }

        return pageSize
    }

    private static func sampleGPUUsage() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var usages: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { service = IOIteratorNext(iterator) }
            defer { IOObjectRelease(service) }

            guard
                let rawStatistics = IORegistryEntryCreateCFProperty(
                    service,
                    "PerformanceStatistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? NSDictionary
            else {
                continue
            }

            for key in [
                "Device Utilization %",
                "GPU Core Utilization",
                "Renderer Utilization %",
                "Tiler Utilization %"
            ] {
                guard let value = numberValue(rawStatistics[key]) else {
                    continue
                }

                usages.append(normalizedGPUUsage(value))
            }
        }

        guard !usages.isEmpty else {
            return nil
        }

        return min(max(usages.max() ?? 0, 0), 1)
    }

    private static func normalizedGPUUsage(_ value: Double) -> Double {
        value > 1 ? value / 100 : value
    }

    private static func numberValue(_ rawValue: Any?) -> Double? {
        if let intValue = rawValue as? Int {
            return Double(intValue)
        }
        if let doubleValue = rawValue as? Double {
            return doubleValue
        }
        if let numberValue = rawValue as? NSNumber {
            return numberValue.doubleValue
        }
        if let stringValue = rawValue as? String {
            return Double(stringValue)
        }
        return nil
    }
}

private struct CPUTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

private extension UInt64 {
    func saturatingDelta(from previous: UInt64) -> UInt64 {
        self >= previous ? self - previous : 0
    }
}
