import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum StickerImageOptimizer {
    static func optimizedData(
        from data: Data,
        aspectRatio: CGFloat = 2.08,
        outputWidth: CGFloat = 1280,
        targetBytes: Int = 420_000
    ) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        let outputSize = CGSize(width: outputWidth, height: outputWidth / aspectRatio)
        let imageAspect = image.size.width / image.size.height

        let drawSize: CGSize
        if imageAspect > aspectRatio {
            drawSize = CGSize(width: outputSize.height * imageAspect, height: outputSize.height)
        } else {
            drawSize = CGSize(width: outputSize.width, height: outputSize.width / imageAspect)
        }

        let drawOrigin = CGPoint(
            x: (outputSize.width - drawSize.width) / 2,
            y: (outputSize.height - drawSize.height) / 2
        )

        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let cropped = renderer.image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }

        var smallestData: Data?
        for quality in [0.84, 0.76, 0.68, 0.60, 0.52] {
            guard let compressed = cropped.jpegData(compressionQuality: quality) else { continue }
            smallestData = compressed
            if compressed.count <= targetBytes {
                return compressed
            }
        }

        return smallestData
        #else
        return nil
        #endif
    }
}
