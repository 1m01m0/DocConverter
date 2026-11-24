import Foundation

/// 平台相关能力的挂钩点。核心库保持跨平台，由 DocCoreMac 等平台模块在启动时注入实现。
public enum Platform {
    /// 把 Office 不支持的图片（WebP / SVG / TIFF / EMF …）转成 PNG。返回 nil 表示无法转换。
    public static var imageTranscoder: ((ImageData) -> ImageData?)? = nil

    /// Office 文档可直接嵌入的图片类型
    static let officeSafeMimes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/bmp"]

    /// 返回可嵌入 Office 文档的图片；无法转换时返回 nil
    public static func officeCompatible(_ img: ImageData) -> ImageData? {
        if officeSafeMimes.contains(img.mime) { return img }
        if var converted = imageTranscoder?(img) {
            converted.alt = img.alt
            return converted
        }
        return nil
    }

    /// 应用名，写入文档属性
    public static let generator = "DocConverter"
}
