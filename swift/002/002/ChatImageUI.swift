//
//  ChatImageUI.swift
//  神算子
//
//  iOS 图片工具：负责 UIImage 的压缩、解码、缩放。
//  存 / 取 Data 由 ChatCore.ChatImageStore 负责，本层只处理平台原生图片类型。
//  macOS 端会有对应的 NSImage 版本，两者互不干扰。
//

import UIKit

enum ChatImageUI {

    /// 发送前压缩到最长边 1400，转成 JPEG Data 交给 ChatCore 存储发送
    static func jpegData(for image: UIImage, maxSide: CGFloat = 1400) -> Data? {
        let prepared = downscale(image, maxSide: maxSide)
        return prepared.jpegData(compressionQuality: 0.72)
    }

    /// 读取并按需缩放（带内存缓存，列表滚动不重复解码）
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String, maxSide limit: CGFloat = 600) -> UIImage? {
        let key = "\(name)@\(Int(limit))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = ChatImageStore.data(name),
              let original = UIImage(data: data) else { return nil }
        let result = downscale(original, maxSide: limit)
        cache.setObject(result, forKey: key)
        return result
    }

    static func downscale(_ image: UIImage, maxSide limit: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return image }
        let scale = min(1, limit / max(w, h))
        guard scale < 1 else { return image }
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
