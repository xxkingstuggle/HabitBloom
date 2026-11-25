import Foundation
import ImageIO
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias StickerDecodedImage = UIImage

extension Image {
    init(stickerImage: StickerDecodedImage) {
        self.init(uiImage: stickerImage)
    }
}
#elseif canImport(AppKit)
import AppKit
typealias StickerDecodedImage = NSImage

extension Image {
    init(stickerImage: StickerDecodedImage) {
        self.init(nsImage: stickerImage)
    }
}
#endif

/// 带像素内存成本上限的贴纸图像解码缓存：
/// 按贴纸内容指纹和目标像素尺寸索引预缩放位图，避免滚动时在主线程反复解码 JPEG 字节。
final class StickerImageCache: @unchecked Sendable {
    static let shared = StickerImageCache()

    private let cache: NSCache<NSString, StickerDecodedImage>
    private let lock = NSLock()

    init(totalCostLimitBytes: Int = 32 * 1024 * 1024, countLimit: Int = 48) {
        let storage = NSCache<NSString, StickerDecodedImage>()
        storage.totalCostLimit = totalCostLimitBytes
        storage.countLimit = countLimit
        self.cache = storage
    }

    func image(for data: Data?, maxPixelSize: CGFloat = 960) -> StickerDecodedImage? {
        guard let data, !data.isEmpty else { return nil }
        let bucket = max(128, Int((maxPixelSize / 64).rounded(.up) * 64))
        let key = "\(widgetImageFingerprint(data))-\(bucket)" as NSString

        lock.lock()
        if let cached = cache.object(forKey: key) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let decoded = decodeThumbnail(from: data, maxPixelSize: CGFloat(bucket)) else {
            return nil
        }

        let cost = pixelMemoryCost(of: decoded.cgImage)
        lock.lock()
        cache.setObject(decoded.image, forKey: key, cost: cost)
        lock.unlock()
        return decoded.image
    }

    func removeAll() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    private func decodeThumbnail(from data: Data, maxPixelSize: CGFloat) -> (image: StickerDecodedImage, cgImage: CGImage)? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return fallbackDecode(from: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return fallbackDecode(from: data)
        }

        #if canImport(UIKit)
        return (UIImage(cgImage: cgImage), cgImage)
        #elseif canImport(AppKit)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return (NSImage(cgImage: cgImage, size: size), cgImage)
        #endif
    }

    private func fallbackDecode(from data: Data) -> (image: StickerDecodedImage, cgImage: CGImage)? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        return (image, cgImage)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return (image, cgImage)
        #endif
    }

    private func pixelMemoryCost(of cgImage: CGImage) -> Int {
        max(1, cgImage.bytesPerRow * cgImage.height)
    }
}

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
