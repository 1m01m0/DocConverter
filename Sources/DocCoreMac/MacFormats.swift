import AppKit
import DocCore

/// 在 macOS 上注册 PDF、RTF/DOC/ODT、图片导出、OCR 与 LibreOffice 等平台能力
public enum MacFormats {
    private static var registered = Set<ObjectIdentifier>()
    private static let lock = NSLock()

    public static func register(on engine: ConversionEngine = .shared) {
        lock.lock(); defer { lock.unlock() }
        guard !registered.contains(ObjectIdentifier(engine)) else { return }
        registered.insert(ObjectIdentifier(engine))
        Platform.imageTranscoder = ImageTools.transcodeToPNG
        engine.register(reader: PDFInputFormat())
        engine.register(writer: PDFOutputFormat())
        engine.register(reader: RichTextFormat())
        engine.register(writer: RichTextFormat())
        engine.register(writer: ImageOutputFormat())
        engine.register(direct: PDFRasterConverter())
        engine.register(direct: LibreOfficeConverter())
    }
}

enum ImageTools {
    /// 用 ImageIO 把 WebP / TIFF / HEIC / SVG(经 NSImage) 等转成 PNG
    static func transcodeToPNG(_ img: ImageData) -> ImageData? {
        if let src = CGImageSourceCreateWithData(img.data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return png(from: cg, alt: img.alt)
        }
        if let ns = NSImage(data: img.data), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return png(from: cg, alt: img.alt)
        }
        return nil
    }

    static func png(from cg: CGImage, alt: String) -> ImageData? {
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let d = rep.representation(using: .png, properties: [:]) else { return nil }
        return ImageData(data: d, mime: "image/png", alt: alt)
    }
}
