import AppKit
import ApplicationServices
import Observation

struct BadgedApp: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let badge: String
    let url: URL?
}

@Observable
@MainActor
final class DockBadgeModel {
    var apps: [BadgedApp] = []
    var hasAccessibilityPermission = AXIsProcessTrusted()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func requestPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else {
            hasAccessibilityPermission = true
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func refresh() async {
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted {
            hasAccessibilityPermission = trusted
        }
        guard trusted else {
            apps = []
            return
        }
        let latest = await Task.detached(priority: .utility) { DockBadgeReader.read() }.value
        if latest != apps { apps = latest }
    }

    func open(_ app: BadgedApp) {
        guard let url = app.url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

private enum DockBadgeReader {
    static func read() -> [BadgedApp] {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return []
        }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        return descendants(of: root).compactMap(badgedApp(from:))
            .uniqued(by: \BadgedApp.id)
    }

    private static func badgedApp(from element: AXUIElement) -> BadgedApp? {
        guard stringAttribute(kAXSubroleAttribute, of: element) == "AXApplicationDockItem",
              let badge = stringAttribute("AXStatusLabel", of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !badge.isEmpty,
              let name = stringAttribute(kAXTitleAttribute, of: element), !name.isEmpty else { return nil }

        let url = urlAttribute(kAXURLAttribute, of: element)
        let id = name
        return BadgedApp(id: id, name: name, badge: badge, url: url)
    }

    private static func descendants(of element: AXUIElement) -> [AXUIElement] {
        var result = [element]
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return result }
        for child in children { result.append(contentsOf: descendants(of: child)) }
        return result
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func urlAttribute(_ name: String, of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? URL
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
