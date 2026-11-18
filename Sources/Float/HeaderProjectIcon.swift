import AppKit
import FloatCore
import SwiftUI

/// T3 uses an explicit override first, then looks for a favicon in the checkout.
struct HeaderProjectIcon: View {
    let project: T3Project?
    let isLocal: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let icon = project?.projectIcon, icon.kind == "emoji", let emoji = icon.emoji {
                Text(emoji).font(.system(size: 10.5))
            } else if let icon = project?.projectIcon, icon.kind == "monogram", let text = icon.text {
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "folder").font(.system(size: 10.5))
            }
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
        .task(id: project) {
            image = nil
            guard isLocal, let project, project.projectIcon == nil else { return }
            let data = await Task.detached { Self.faviconData(for: project) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
        }
    }

    private nonisolated static func faviconData(for project: T3Project) -> Data? {
        let root = URL(fileURLWithPath: project.workspaceRoot, isDirectory: true).resolvingSymlinksInPath()
        func read(_ path: String, allowAbsolute: Bool = false) -> Data? {
            let file: URL
            if path.hasPrefix("/"), allowAbsolute {
                file = URL(fileURLWithPath: path)
            } else {
                file = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else { return nil }
            }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize,
                  (1...2_000_000).contains(size) else { return nil }
            return try? Data(contentsOf: file)
        }

        if let path = project.faviconPath, let data = read(path, allowAbsolute: true) { return data }
        struct ProjectFile: Decodable { let iconPath: String? }
        if let file = read("t3.json"),
           let path = (try? JSONDecoder().decode(ProjectFile.self, from: file))?.iconPath,
           let data = read(path) { return data }

        // Keep this order aligned with T3's ProjectFaviconResolver.
        let candidates = [
            "favicon.svg", "favicon.ico", "favicon.png",
            "public/favicon.svg", "public/favicon.ico", "public/favicon.png",
            "app/favicon.ico", "app/favicon.png", "app/icon.svg", "app/icon.png", "app/icon.ico",
            "src/favicon.ico", "src/favicon.svg", "src/app/favicon.ico", "src/app/icon.svg", "src/app/icon.png",
            "assets/icon.svg", "assets/icon.png", "assets/logo.svg", "assets/logo.png",
            ".idea/icon.svg", "Resources/AppIcon.icns", "AppIcon.icns",
        ]
        if let data = candidates.lazy.compactMap({ read($0) }).first { return data }

        let sourcePaths = [
            "index.html", "public/index.html", "app/routes/__root.tsx", "src/routes/__root.tsx",
            "app/root.tsx", "src/root.tsx", "src/index.html",
        ]
        let link = #"<link\b(?=[^>]*\brel=["'](?:icon|shortcut icon)["'])(?=[^>]*\bhref=["']([^"'?]+))[^>]*>"#
        let rel = #"\brel\s*:\s*["'](?:icon|shortcut icon)["']"#
        let href = #"\bhref\s*:\s*["']([^"'?]+)"#
        let linkPattern = try? NSRegularExpression(pattern: link, options: .caseInsensitive)
        let hrefPattern = try? NSRegularExpression(pattern: href, options: .caseInsensitive)
        for path in sourcePaths {
            guard let data = read(path), let source = String(data: data, encoding: .utf8) else { continue }
            let icon = capturedPath(in: source, with: linkPattern) ?? source.split(separator: "}").lazy
                .filter { $0.range(of: rel, options: [.regularExpression, .caseInsensitive]) != nil }
                .compactMap { capturedPath(in: String($0), with: hrefPattern) }.first
            guard let icon else { continue }
            let localPath = icon.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !localPath.contains(":"), !localPath.hasPrefix("//") else { continue }
            let relative = localPath.hasPrefix("/") ? String(localPath.dropFirst()) : localPath
            if let data = read("public/\(relative)") ?? read(relative) { return data }
        }
        return nil
    }

    private nonisolated static func capturedPath(in source: String, with pattern: NSRegularExpression?) -> String? {
        guard let match = pattern?.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let captured = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[captured])
    }
}
