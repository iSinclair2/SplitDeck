import AppKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreview: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(5)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size * 2, height: size * 2), scale: 2, representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

private extension QLThumbnailRepresentation {
    var nsImage: NSImage { NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)) }
}
