import Foundation
import ImageIO
import UIKit
import os

/// 缩略图生成器
///
/// 用 ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` 生成缩略图：
/// 它不需要把整张原图解码进内存（一张 4800 万像素的照片解码后要占上百 MB 内存），
/// 而是"边读边缩"，非常省内存、省电池——这正是记账 App 每天高频要做的事。
enum ThumbnailGenerator {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "thumbnail")

    /// 生成缩略图
    /// - Parameters:
    ///   - data: 原图的二进制数据
    ///   - maxPixel: 缩略图最长边的像素数（默认 400，在列表里显示足够清晰）
    /// - Returns: 压缩后的 JPEG 数据；失败时返回 nil（调用方就不存缩略图）
    static func thumbnail(from data: Data, maxPixel: CGFloat = 400) -> Data? {
        guard !data.isEmpty else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            logger.warning("无法读取图片数据，缩略图生成失败")
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,  // 即使原图自带缩略图也重新生成，保证尺寸准确
            kCGImageSourceCreateThumbnailWithTransform: true,     // 自动按 EXIF 方向摆正（手机竖拍不会躺倒）
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            logger.warning("缩略图解码失败")
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        // 压缩质量 0.7：肉眼几乎无差别，体积只有原图的几十分之一
        let jpeg = image.jpegData(compressionQuality: 0.7)
        if jpeg == nil {
            logger.warning("JPEG 压缩失败")
        }
        return jpeg
    }
}
