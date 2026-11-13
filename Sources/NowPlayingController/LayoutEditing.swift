import Observation
import SwiftUI

/// Whether the deck is being edited, and the drag in flight. Shared by the main deck and
/// the layout drawer so a widget can be dragged from the drawer straight onto the deck.
@Observable
@MainActor
final class LayoutEditSession {
    static let shared = LayoutEditSession()

    var isEditing = false
    /// "new:<kind>:<size>" from the drawer, or "move:<uuid>" for a widget already placed.
    var payload: String?
    /// The most recently added widget, so the deck can scroll to it and highlight it.
    var lastAdded: UUID?

    private init() { }

    func noteAdded(before: [WidgetInstance], after: [WidgetInstance]) {
        let existing = Set(before.map(\.id))
        if let added = after.first(where: { !existing.contains($0.id) && $0.zone == "body" }) { lastAdded = added.id }
    }

    func begin() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isEditing = true }
    }

    func end() {
        payload = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isEditing = false }
    }
}

/// Widget categories for the drawer.
enum WidgetGroups {
    static let all: [(name: String, icon: String, kinds: [String])] = [
        ("Time & Calendar", "calendar", ["clock", "calendar", "meeting", "month", "clocks", "countdown", "holidays"]),
        ("Productivity", "checklist", ["focus", "reminders", "habits", "scratchpad", "clipboard", "shortcuts", "converter"]),
        ("Files & Apps", "folder", ["shelf", "recent", "launcher", "disks"]),
        ("Media & Photos", "play.square", ["media", "audio", "photos"]),
        ("Weather & Outdoors", "cloud.sun", ["forecast", "airquality", "sunmoon"]),
        ("System & Network", "gauge.with.dots.needle.67percent", ["system", "performance", "network", "speedtest", "publicip", "bluetooth", "toggles", "notifications"]),
        ("News & Markets", "newspaper", ["news", "hackernews", "onthisday", "currency", "crypto"])
    ]
}

/// Pure layout mutations: placing, moving, resizing and removing widgets on a fixed-column
/// grid, pushing anything that collides to the nearest free cell.
struct LayoutEditing {
    var instances: [WidgetInstance]
    let columns: Int

    init(_ instances: [WidgetInstance], columns: Int) {
        self.instances = instances
        self.columns = max(1, columns)
    }

    static func span(_ size: String) -> WidgetSpan {
        switch size { case "large": return WidgetSpan(columns: 2, rows: 2); case "medium": return WidgetSpan(columns: 2, rows: 1); default: return WidgetSpan(columns: 1, rows: 1) }
    }

    /// The footprint a payload will occupy, for drawing the drop outline.
    func span(of payload: String) -> WidgetSpan {
        if payload.hasPrefix("move:"), let id = UUID(uuidString: String(payload.dropFirst(5))), let item = instances.first(where: { $0.id == id }) {
            return Self.span(item.size)
        }
        if payload.hasPrefix("new:") { return Self.span(payload.split(separator: ":").last.map(String.init) ?? "small") }
        return WidgetSpan(columns: 1, rows: 1)
    }

    /// Applies a drop. `zone` is "body", "header" or "footer"; `position` is the grid cell
    /// for body drops (nil appends to the first free space).
    @discardableResult
    mutating func drop(_ payload: String, zone: String, at position: WidgetPosition? = nil) -> Bool {
        var moving: WidgetInstance
        var originalZone: String?
        if payload.hasPrefix("new:") {
            let parts = payload.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { return false }
            moving = WidgetInstance(kind: parts[1], size: parts.count > 2 ? parts[2] : "small", zone: zone)
        } else if payload.hasPrefix("move:"), let id = UUID(uuidString: String(payload.dropFirst(5))), let index = instances.firstIndex(where: { $0.id == id }) {
            moving = instances.remove(at: index)
            originalZone = moving.zone
            moving.zone = zone
        } else {
            return false
        }

        if zone == "header" || zone == "footer" {
            // One banner per zone: the current occupant swaps into the dragged widget's old
            // banner slot, or drops back into the grid.
            for index in instances.indices where instances[index].zone == zone {
                if let originalZone, originalZone == "header" || originalZone == "footer" {
                    instances[index].zone = originalZone
                } else {
                    instances[index].zone = "body"
                }
                instances[index].column = nil
                instances[index].row = nil
            }
            if moving.size == "large" { moving.size = "medium" }
            moving.column = nil
            moving.row = nil
            instances.append(moving)
        } else {
            moving.column = position?.column
            moving.row = position?.row
            if moving.kind == "audio" && moving.size == "large" { moving.size = "medium" }
            place(moving)
        }
        normalise()
        return true
    }

    mutating func setSettings(_ id: UUID, _ settings: [String: String]) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].settings = settings.isEmpty ? nil : settings
    }

    mutating func remove(_ id: UUID) {
        instances.removeAll { $0.id == id }
        normalise()
    }

    mutating func setSize(_ id: UUID, _ size: String) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        var moving = instances.remove(at: index)
        moving.size = moving.kind == "audio" && size == "large" ? "medium" : size
        place(moving)
        normalise()
    }

    /// Maps a drag on the resize handle to a size, the way the corner of a window would.
    static func resizedSize(from original: String, translation: CGSize) -> String {
        switch original {
        case "small":
            if translation.width > 35 && translation.height > 35 { return "large" }
            if translation.width > 35 { return "medium" }
            return "small"
        case "medium":
            if translation.height > 30 { return "large" }
            if translation.width < -25 { return "small" }
            return "medium"
        case "large":
            if translation.width < -25 && translation.height < -25 { return "small" }
            if translation.height < -25 { return "medium" }
            return "large"
        default:
            return original
        }
    }

    // MARK: Placement

    private mutating func place(_ input: WidgetInstance) {
        var moving = input
        let width = min(Self.span(moving.size).columns, columns)
        guard let row = moving.row else {
            moving.column = nil
            instances.append(moving)
            return
        }
        moving.column = min(max(0, moving.column ?? 0), columns - width)
        let column = moving.column ?? 0
        let movingSpan = Self.span(moving.size)
        let colliding = Set(instances.filter { item in
            guard item.zone == "body", let c = item.column, let r = item.row else { return false }
            return Self.overlaps(c, r, Self.span(item.size), column, row, movingSpan)
        }.map(\.id))
        var occupied = occupiedCells(excluding: colliding)
        mark(column, row, movingSpan, in: &occupied)
        for id in colliding {
            guard let index = instances.firstIndex(where: { $0.id == id }) else { continue }
            let itemSpan = Self.span(instances[index].size)
            let origin = WidgetPosition(column: instances[index].column ?? 0, row: instances[index].row ?? 0)
            let destination = nearestFree(to: origin, span: itemSpan, occupied: occupied)
            instances[index].column = destination.column
            instances[index].row = destination.row
            mark(destination.column, destination.row, itemSpan, in: &occupied)
        }
        instances.append(moving)
    }

    private mutating func normalise() {
        instances = WidgetLayoutStore.resolved(instances, columns: columns)
    }

    private func occupiedCells(excluding ids: Set<UUID>) -> Set<String> {
        var cells = Set<String>()
        for item in instances where item.zone == "body" && !ids.contains(item.id) {
            if let column = item.column, let row = item.row { mark(column, row, Self.span(item.size), in: &cells) }
        }
        return cells
    }

    private func nearestFree(to origin: WidgetPosition, span itemSpan: WidgetSpan, occupied: Set<String>) -> WidgetPosition {
        for distance in 0...40 {
            for row in 0...(origin.row + distance + 2) {
                for column in 0..<columns where abs(column - origin.column) + abs(row - origin.row) == distance {
                    if fits(column, row, itemSpan, occupied: occupied) { return WidgetPosition(column: column, row: row) }
                }
            }
        }
        return WidgetPosition(column: 0, row: origin.row + 41)
    }

    private func fits(_ column: Int, _ row: Int, _ itemSpan: WidgetSpan, occupied: Set<String>) -> Bool {
        guard column >= 0, row >= 0, column + itemSpan.columns <= columns else { return false }
        for r in row..<(row + itemSpan.rows) { for c in column..<(column + itemSpan.columns) where occupied.contains("\(c):\(r)") { return false } }
        return true
    }

    private func mark(_ column: Int, _ row: Int, _ itemSpan: WidgetSpan, in cells: inout Set<String>) {
        for r in row..<(row + itemSpan.rows) { for c in column..<(column + itemSpan.columns) { cells.insert("\(c):\(r)") } }
    }

    private static func overlaps(_ c1: Int, _ r1: Int, _ s1: WidgetSpan, _ c2: Int, _ r2: Int, _ s2: WidgetSpan) -> Bool {
        c1 < c2 + s2.columns && c2 < c1 + s1.columns && r1 < r2 + s2.rows && r2 < r1 + s1.rows
    }
}
