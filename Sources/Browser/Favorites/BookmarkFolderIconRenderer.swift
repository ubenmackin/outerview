// Favorites — Folder preview badge and star badge renderer.

import UIKit

@MainActor
enum BookmarkFolderIconRenderer {
    /// Renders a Safari-style pinned Favorites badge (vibrant blue rounded rect with white star).
    static func favoritesBadge(size: CGFloat = 30, cornerRadius: CGFloat = 6) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            UIColor.systemBlue.setFill()
            path.fill()

            let config = UIImage.SymbolConfiguration(pointSize: size * 0.52, weight: .bold)
            if let star = UIImage(systemName: "star.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let starSize = star.size
                let starRect = CGRect(
                    x: (size - starSize.width) / 2,
                    y: (size - starSize.height) / 2,
                    width: starSize.width,
                    height: starSize.height
                )
                star.draw(in: starRect)
            }
        }
    }

    /// Renders a Safari-style folder badge with a 2x2 grid of mini-favicons/monograms.
    static func folderBadge(
        for _: BookmarkFolder,
        previewBookmarks: [Bookmark],
        size: CGFloat = 30,
        cornerRadius: CGFloat = 6
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            let bgColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.22, alpha: 1.0)
                    : UIColor(white: 0.88, alpha: 1.0)
            }
            bgColor.setFill()
            bgPath.fill()

            if previewBookmarks.isEmpty {
                let config = UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
                let symbolColor = UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 0.65, alpha: 1.0)
                        : UIColor(white: 0.45, alpha: 1.0)
                }
                if let folderImg = UIImage(systemName: "folder.fill", withConfiguration: config)?.withTintColor(symbolColor, renderingMode: .alwaysOriginal) {
                    let sSize = folderImg.size
                    let sRect = CGRect(
                        x: (size - sSize.width) / 2,
                        y: (size - sSize.height) / 2,
                        width: sSize.width,
                        height: sSize.height
                    )
                    folderImg.draw(in: sRect)
                }
                return
            }

            let padding: CGFloat = max(2, floor(size * 0.08))
            let spacing: CGFloat = max(1.5, floor(size * 0.06))
            let availableWidth = size - (2 * padding) - spacing
            let cellSize = floor(availableWidth / 2)
            let cellRadius = max(2, floor(cellSize * 0.24))

            let quadrants: [(col: CGFloat, row: CGFloat)] = [
                (0, 0), (1, 0),
                (0, 1), (1, 1)
            ]

            for (index, bookmark) in previewBookmarks.prefix(4).enumerated() {
                let quad = quadrants[index]
                let cellX = padding + quad.col * (cellSize + spacing)
                let cellY = padding + quad.row * (cellSize + spacing)
                let cellRect = CGRect(x: cellX, y: cellY, width: cellSize, height: cellSize)

                let icon = FaviconService.shared.cachedFaviconOrMonogram(for: bookmark.url, size: cellSize)
                ctx.cgContext.saveGState()
                let clipPath = UIBezierPath(roundedRect: cellRect, cornerRadius: cellRadius)
                clipPath.addClip()
                icon.draw(in: cellRect)
                ctx.cgContext.restoreGState()
            }
        }
    }
}
