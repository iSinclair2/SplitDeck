import AppKit

extension NSImage {
    var splitDeckContrastAccent: NSColor? {
        let size = NSSize(width: 28, height: 28)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var bins = Array(repeating: (weight: CGFloat(0), hue: CGFloat(0), saturation: CGFloat(0), brightness: CGFloat(0)), count: 24)
        for y in 0..<28 { for x in 0..<28 {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            if brightness > 0.12 && brightness < 0.97 && saturation > 0.22 {
                let index = min(23, Int(hue * 24))
                let weight = saturation * saturation * (0.45 + brightness * 0.55)
                bins[index].weight += weight
                bins[index].hue += hue * weight
                bins[index].saturation += saturation * weight
                bins[index].brightness += brightness * weight
            }
        } }
        guard let dominant = bins.max(by: { $0.weight < $1.weight }), dominant.weight > 0 else { return nil }
        let hue = dominant.hue / dominant.weight
        let saturation = max(0.68, min(1, dominant.saturation / dominant.weight * 1.18))
        let brightness = max(0.48, min(0.82, dominant.brightness / dominant.weight))
        return NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
