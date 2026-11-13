import SwiftUI

struct WidgetSpan: Equatable {
    let columns: Int
    let rows: Int
}

struct WidgetSpanKey: LayoutValueKey {
    static let defaultValue = WidgetSpan(columns: 1, rows: 1)
}

struct WidgetPosition: Equatable { let column: Int; let row: Int }
struct WidgetPositionKey: LayoutValueKey {
    static let defaultValue: WidgetPosition? = nil
}

struct WidgetGridLayout: Layout {
    var spacing: CGFloat = 12
    var minimumCellWidth: CGFloat = 170
    var rowHeight: CGFloat? = nil
    var fixedColumnCount: Int? = nil

    struct Cache {
        var frames: [CGRect] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = max(minimumCellWidth, proposal.width ?? minimumCellWidth)
        let columnCount = max(1, fixedColumnCount ?? Int((width + spacing) / (minimumCellWidth + spacing)))
        let cellWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        let resolvedRowHeight = rowHeight ?? cellWidth
        var occupied: [[Bool]] = []
        var frames: [CGRect] = []

        func fits(row: Int, column: Int, span: WidgetSpan) -> Bool {
            guard column + span.columns <= columnCount else { return false }
            for r in row..<(row + span.rows) {
                if r < occupied.count {
                    for c in column..<(column + span.columns) where occupied[r][c] { return false }
                }
            }
            return true
        }

        for subview in subviews {
            var span = subview[WidgetSpanKey.self]
            span = WidgetSpan(columns: min(span.columns, columnCount), rows: span.rows)
            var row = max(0, subview[WidgetPositionKey.self]?.row ?? 0)
            var column = max(0, min(columnCount - span.columns, subview[WidgetPositionKey.self]?.column ?? 0))
            let requestedPosition = subview[WidgetPositionKey.self] != nil
            search: while !requestedPosition || !fits(row: row, column: column, span: span) {
                while occupied.count < row + span.rows { occupied.append(Array(repeating: false, count: columnCount)) }
                for candidate in 0..<columnCount where fits(row: row, column: candidate, span: span) {
                    column = candidate
                    break search
                }
                row += 1
            }
            while occupied.count < row + span.rows { occupied.append(Array(repeating: false, count: columnCount)) }
            for r in row..<(row + span.rows) { for c in column..<(column + span.columns) { occupied[r][c] = true } }
            frames.append(CGRect(
                x: CGFloat(column) * (cellWidth + spacing),
                y: CGFloat(row) * (resolvedRowHeight + spacing),
                width: CGFloat(span.columns) * cellWidth + CGFloat(span.columns - 1) * spacing,
                height: CGFloat(span.rows) * resolvedRowHeight + CGFloat(span.rows - 1) * spacing
            ))
        }
        let rows = occupied.count
        cache.frames = frames
        cache.size = CGSize(width: width, height: rows == 0 ? 0 : CGFloat(rows) * resolvedRowHeight + CGFloat(rows - 1) * spacing)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.frames.count != subviews.count { _ = sizeThatFits(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews, cache: &cache) }
        for (subview, frame) in zip(subviews, cache.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
