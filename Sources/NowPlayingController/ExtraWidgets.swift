import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class ExtraWidgetsModel {
    var wifi = "Checking network…"
    var network = NetworkStatus()
    var cpu = "—"
    var cpuPercent: Double?
    var memory = "—"
    var volume = 0.0
    var isMuted = false
    var cpuHistory: [Double] = []
    var networkHistory: [Double] = []
    var storage = "—"
    var recentFiles: [URL] = []
    enum FolderAccess { case notRequested, granted, denied }
    /// Recent Files reads Documents and Downloads only after the user asks it to, so the
    /// macOS folder prompt appears in response to a click rather than at launch.
    var recentFilesAccess: FolderAccess = UserDefaults.standard.bool(forKey: "recentFilesAccessRequested") ? .granted : .notRequested
    var launcherApps: [URL] = []
    var wifiPassword: String?
    private var started = false
    private var lastNetworkBytes: Double?
    private var volumeTask: Task<Void, Never>?
    private var refreshTick = 0

    func start() {
        guard !started else { return }
        started = true
        if recentFilesAccess != .notRequested { refreshFiles() }
        launcherApps = (UserDefaults.standard.stringArray(forKey: "launcherPaths") ?? []).map(URL.init(fileURLWithPath:))
        Task {
            while !Task.isCancelled {
                let values = await Task.detached(priority: .utility) {
                    (
                        Self.networkStatus(),
                        Self.run("/usr/bin/top", ["-l", "1", "-n", "0"]),
                        Self.run("/usr/bin/vm_stat", []),
                        Self.run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"]),
                        Self.run("/usr/bin/osascript", ["-e", "output muted of (get volume settings)"]),
                        Self.run("/usr/sbin/netstat", ["-ibn"])
                    )
                }.value
                network = values.0
                wifi = values.0.summary
                if let idle = Self.firstMatch(in: values.1, pattern: #"([\d.]+)% idle"#).flatMap(Double.init) {
                    let busy = max(0, min(100, 100 - idle))
                    cpuPercent = busy
                    cpu = String(format: "%.0f%% CPU", busy)
                    cpuHistory.append(busy); cpuHistory = Array(cpuHistory.suffix(24))
                } else {
                    cpu = "CPU unavailable"
                }
                memory = Self.memorySummary(values.2)
                // Don't fight the slider while the user is dragging it.
                if volumeTask == nil { volume = Double(values.3.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
                isMuted = values.4.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                let bytes = Self.networkBytes(values.5)
                if let previous = lastNetworkBytes { networkHistory.append(min(100, max(0, (bytes - previous) / 1_000_000))); networkHistory = Array(networkHistory.suffix(30)) }
                lastNetworkBytes = bytes
                if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) {
                    storage = ByteCountFormatter.string(fromByteCount: values.volumeAvailableCapacityForImportantUsage ?? 0, countStyle: .file) + " free"
                }
                refreshTick += 1
                if refreshTick.isMultiple(of: 6), recentFilesAccess == .granted { refreshFiles() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Coalesces slider changes so dragging doesn't launch a process per pixel.
    func setVolume(_ value: Double) {
        volume = value
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let level = Int(value.rounded())
            await Task.detached { _ = Self.run("/usr/bin/osascript", ["-e", "set volume output volume \(level)"]) }.value
            if !Task.isCancelled { volumeTask = nil }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        let value = isMuted ? "true" : "false"
        Task.detached { _ = Self.run("/usr/bin/osascript", ["-e", "set volume output muted \(value)"]) }
    }

    func loadWifiPassword() {
        let network = wifi
        Task {
            let password = await Task.detached(priority: .userInitiated) {
                Self.run("/usr/bin/security", ["find-generic-password", "-D", "AirPort network password", "-a", network, "-w"])
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            wifiPassword = password.isEmpty ? nil : password
        }
    }

    func addLaunchers(_ urls: [URL]) {
        for url in urls where !launcherApps.contains(url) { launcherApps.append(url) }
        launcherApps = Array(launcherApps.prefix(8))
        UserDefaults.standard.set(launcherApps.map(\.path), forKey: "launcherPaths")
    }

    func removeLauncher(_ url: URL) {
        launcherApps.removeAll { $0 == url }
        UserDefaults.standard.set(launcherApps.map(\.path), forKey: "launcherPaths")
    }

    /// Reading Documents/Downloads can block on a system privacy prompt, so it must never
    /// run on the main thread or the whole window freezes until the prompt is answered.
    func requestRecentFilesAccess() {
        UserDefaults.standard.set(true, forKey: "recentFilesAccessRequested")
        recentFilesAccess = .granted
        refreshFiles()
    }

    func refreshFiles() {
        Task {
            let result = await Task.detached(priority: .utility) { Self.recentFileURLs() }.value
            recentFiles = result.files
            recentFilesAccess = result.denied ? .denied : .granted
        }
    }

    nonisolated private static func recentFileURLs() -> (files: [URL], denied: Bool) {
        let roots = [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                     FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first].compactMap { $0 }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var candidates: [URL] = []
        var denied = false
        for root in roots {
            do {
                candidates.append(contentsOf: try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]))
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                denied = true
            } catch {
                continue
            }
        }
        let regularFiles = candidates.filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }
        let files = regularFiles.sorted {
                ((try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast)
            }.prefix(8).map { $0 }
        return (files, denied && files.isEmpty)
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try? process.run(); process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    nonisolated private static func networkStatus() -> NetworkStatus {
        let ports = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        var status = NetworkStatus()
        for block in ports.components(separatedBy: "\n\n") {
            guard let port = firstMatch(in: block, pattern: #"Hardware Port: ([^\n]+)"#),
                  let device = firstMatch(in: block, pattern: #"Device: (\S+)"#) else { continue }
            let isWiFi = port.contains("Wi-Fi") || port.contains("AirPort")
            // Bridges, Bluetooth and tethered phones aren't what people mean by "Ethernet";
            // any other wired port (including USB LAN adapters) is.
            let ignored = ["Bluetooth", "Thunderbolt Bridge", "iPhone", "iPad", "VPN"].contains { port.contains($0) }
            guard isWiFi || !ignored else { continue }
            // A port only counts as connected once it has an address, not just a link.
            let address = run("/usr/sbin/ipconfig", ["getifaddr", device]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            if isWiFi {
                status.wifiConnected = true
                // macOS only reveals the network name to apps with Location access; fall
                // back to the address so the row still says something useful.
                let result = run("/usr/sbin/networksetup", ["-getairportnetwork", device])
                let name = result.localizedCaseInsensitiveContains("not associated") ? ""
                    : result.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                status.wifiDetail = name.isEmpty ? address : "\(name) · \(address)"
            } else if !status.ethernetConnected {
                status.ethernetConnected = true
                status.ethernetDetail = address
            }
        }
        return status
    }

    nonisolated private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    nonisolated private static func memorySummary(_ text: String) -> String {
        let pageSize = firstMatch(in: text, pattern: #"page size of (\d+) bytes"#).flatMap(Double.init) ?? 16_384
        func pages(_ label: String) -> Double {
            guard let value = firstMatch(in: text, pattern: "\(label):\\s+(\\d+)") else { return 0 }
            return Double(value) ?? 0
        }
        let used = (pages("Pages active") + pages("Pages wired down") + pages("Pages occupied by compressor")) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return used > 0 ? String(format: "%.1f of %.0f GB used", used / 1_073_741_824, total) : "Memory unavailable"
    }

    nonisolated private static func networkBytes(_ text: String) -> Double {
        text.split(separator: "\n").dropFirst().reduce(0) { total, line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count > 9, fields[0].hasPrefix("en") else { return total }
            return total + (Double(fields[6]) ?? 0) + (Double(fields[9]) ?? 0)
        }
    }
}

struct NetworkStatus: Sendable, Equatable {
    var wifiConnected = false
    var wifiDetail = "Not connected"
    var ethernetConnected = false
    var ethernetDetail = "Not connected"

    var summary: String {
        let active = [wifiConnected ? "Wi-Fi" : nil, ethernetConnected ? "Ethernet" : nil].compactMap { $0 }
        return active.isEmpty ? "Not connected" : active.joined(separator: " + ")
    }
}

@MainActor
enum SplitDeckGlobalShortcut {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift], event.keyCode == 49 else { return }
            Task { @MainActor in
                guard let window = NSApplication.shared.windows.first(where: { !($0 is NSPanel) }) else { return }
                if window.isVisible && NSApplication.shared.isActive { window.orderOut(nil) }
                else { NSApplication.shared.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
            }
        }
    }
}
