import AppKit
import PDFKit
import DocCore

// MARK: - 图片输出（PNG / JPEG）
// PDF 直接按页栅格化；其他格式先排版成 PDF 再栅格化。单页输出一个文件，多页输出到同名文件夹。

enum Rasterizer {
    static func render(page: PDFPage, dpi: Double, background: NSColor = .white) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rotation = page.rotation % 360
        let rotated = rotation == 90 || rotation == 270
        let wPt = rotated ? box.height : box.width
        let hPt = rotated ? box.width : box.height
        let scale = CGFloat(dpi / 72.0)
        let w = max(1, Int(wPt * scale)), h = max(1, Int(hPt * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    static func encode(_ img: CGImage, format: Format) -> Data? {
        let rep = NSBitmapImageRep(cgImage: img)
        if format == .jpg { return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) }
        return rep.representation(using: .png, properties: [:])
    }

    /// 把 PDF 的所有页面写成图片，返回输出文件（或文件夹）
    static func write(pdf: PDFDocument, to url: URL, format: Format, dpi: Double) throws -> [URL] {
        let count = pdf.pageCount
        guard count > 0 else { throw ConversionError.emptyDocument }
        if count == 1, let page = pdf.page(at: 0), let img = render(page: page, dpi: dpi), let d = encode(img, format: format) {
            try d.write(to: url)
            return [url]
        }
        let dir = ConversionEngine.uniqueDirectory(in: url.deletingLastPathComponent(), base: url.deletingPathExtension().lastPathComponent)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let digits = String(count).count
        for i in 0..<count {
            guard let page = pdf.page(at: i), let img = render(page: page, dpi: dpi), let d = encode(img, format: format) else { continue }
            let n = String(i + 1).leftPad(digits)
            try d.write(to: dir.appendingPathComponent("page-\(n).\(format.fileExtension)"))
        }
        return [dir]
    }
}

extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}

/// 任意文档 → 排版为 PDF → 图片
struct ImageOutputFormat: DocumentWriter {
    var formats: [Format] { [.png, .jpg] }
    func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        // 只含一张图片的文档（例如 PNG → JPG）直接转码，不加页边距
        if doc.blocks.count == 1, case .image(let img) = doc.blocks[0],
           let src = CGImageSourceCreateWithData(img.data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
           let d = Rasterizer.encode(cg, format: format) {
            try d.write(to: url)
            return [url]
        }
        let data = try PDFRenderer.render(doc, options: options)
        guard let pdf = PDFDocument(data: data) else { throw ConversionError.toolFailed(L.pdfLayoutFailed) }
        return try Rasterizer.write(pdf: pdf, to: url, format: format, dpi: options.imageDPI)
    }
}

/// PDF → PNG/JPEG 直接栅格化，保留原始版式
struct PDFRasterConverter: DirectConverter {
    var name: String { L.pdfRasterizer }
    func canConvert(from: Format, to: Format, options: ConversionOptions) -> Bool {
        from == .pdf && (to == .png || to == .jpg)
    }
    func convert(_ input: URL, from: Format, to: Format, output: URL, options: ConversionOptions) throws -> [URL] {
        guard let pdf = PDFDocument(url: input) else { throw ConversionError.invalidFile(L.cannotOpenPDF) }
        if pdf.isLocked && !pdf.unlock(withPassword: "") { throw ConversionError.invalidFile(L.pdfEncrypted) }
        return try Rasterizer.write(pdf: pdf, to: output, format: to, dpi: options.imageDPI)
    }
}
