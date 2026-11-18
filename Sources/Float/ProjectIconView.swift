import AppKit
import FloatCore
import ImageIO
import SwiftUI

struct ProjectIconView: View {
    let project: T3Project?
    let environmentID: String?
    let size: CGFloat
    var fallbackTitle: String? = nil

    @Environment(\.projectFaviconCache) private var cache
    @State private var loaded: (key: ProjectFaviconCache.Key, image: CGImage)?

    var body: some View {
        let override = project?.projectIcon
        let title = project?.title ?? fallbackTitle
        let key = override == nil ? project.map { ProjectFaviconCache.Key($0, environmentID: environmentID) } : nil
        Group {
            if override?.kind == "monogram", let text = override?.text, let color = overrideColor {
                monogram(text, color: color)
            } else if override?.kind == "emoji", let emoji = override?.emoji {
                Text(emoji).font(.system(size: size * 0.8)).lineLimit(1)
            } else if override?.kind == "lucide", let name = override?.name,
                      let symbol = Self.symbols[name], let color = overrideColor {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color.darkColor)
            } else if let key, let favicon = cache?.image(for: key) ?? (loaded?.key == key ? loaded?.image : nil) {
                Image(decorative: favicon, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size / 4))
            } else if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let identity = T3ProjectIdentity.derive(from: title)
                monogram(identity.monogram, color: identity.color)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            guard let key, let project, let cache else { return }
            let image = await cache.load(project, key: key)
            if let image, !Task.isCancelled { loaded = (key, image) }
        }
    }

    private var overrideColor: T3ProjectIconColor? {
        project?.projectIcon?.color.flatMap(T3ProjectIconColor.init(rawValue:))
    }

    private func monogram(_ text: String, color: T3ProjectIconColor) -> some View {
        Text(text)
            .font(.system(size: size * 0.54, weight: .bold, design: .monospaced))
            .tracking(-0.2)
            .foregroundStyle(color.darkColor)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, size / 8)
            .frame(width: size, height: size)
            .background(color.darkColor.opacity(0.14), in: RoundedRectangle(cornerRadius: size / 4))
    }

    private static let symbols: [String: String] = [
        "archive": "archivebox", "book": "book", "book-open": "book",
        "box": "shippingbox", "briefcase": "briefcase", "camera": "camera",
        "chart-bar": "chart.bar", "cloud": "cloud", "code": "chevron.left.forwardslash.chevron.right",
        "code-xml": "chevron.left.forwardslash.chevron.right", "database": "cylinder",
        "file": "doc", "file-code": "doc.badge.gearshape", "flask-conical": "flask",
        "folder": "folder", "folder-code": "folder.badge.gearshape",
        "git-branch": "arrow.triangle.branch", "globe": "globe", "image": "photo",
        "images": "photo.on.rectangle", "layers": "square.3.layers.3d",
        "layout-dashboard": "rectangle.split.2x2", "package": "shippingbox",
        "rocket": "paperplane", "server": "server.rack", "settings": "gearshape",
        "star": "star", "terminal": "terminal", "wrench": "wrench", "zap": "bolt",
    ]
}

@MainActor
final class ProjectFaviconCache {
    struct Key: Hashable {
        let environmentID: String?
        let workspaceRoot: String
        let path: String?

        init(_ project: T3Project, environmentID: String?) {
            self.environmentID = environmentID
            workspaceRoot = project.workspaceRoot
            path = project.faviconPath
        }
    }

    private enum Entry {
        case loading(Task<CGImage?, Error>)
        case resolved(CGImage?)
    }

    private let client: T3Client
    private var entries: [Key: Entry] = [:]

    init(client: T3Client) {
        self.client = client
    }

    func image(for key: Key) -> CGImage? {
        if case .resolved(let image) = entries[key] { return image }
        return nil
    }

    func load(_ project: T3Project, key: Key) async -> CGImage? {
        switch entries[key] {
        case .resolved(let image): return image
        case .loading(let task): return try? await task.value
        case nil: break
        }

        // The cache owns the task so closing one picker row won't cancel a shared load.
        let task = Task.detached { [client] in
            guard let data = try await client.projectFavicon(project, environmentID: key.environmentID) else {
                return nil as CGImage?
            }
            return Self.decode(data)
        }
        entries[key] = .loading(task)
        do {
            let image = try await task.value
            entries[key] = .resolved(image)
            return image
        } catch {
            entries[key] = nil
            return nil
        }
    }

    private nonisolated static func decode(_ data: Data) -> CGImage? {
        // ImageIO downscales raster formats. AppKit also handles SVG favicons.
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ] as CFDictionary
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
            return image
        }
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

extension EnvironmentValues {
    @Entry var projectFaviconCache: ProjectFaviconCache?
}
