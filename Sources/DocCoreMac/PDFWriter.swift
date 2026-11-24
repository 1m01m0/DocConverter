import AppKit
import DocCore

// MARK: - PDF 输出：TextKit 1 手动分页 + CoreGraphics PDF 上下文
// 不依赖打印面板或主线程，可在后台线程运行；支持表格（NSTextTable）、图片附件、中文字体回退、超链接。

public struct PDFOutputFormat: DocumentWriter {
    public var formats: [Format] { [.pdf] }
    public init() {}

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let data = try PDFRenderer.render(doc, options: options)
        try data.write(to: url)
        return [url]
    }
}

public enum PDFRenderer {
    public static func render(_ doc: Document, options: ConversionOptions) throws -> Data {
        let attr = AttributedBuilder(options: options).build(doc)
        return try render(attributed: attr, options: options, title: doc.effectiveTitle, author: doc.author)
    }

    public static func render(attributed: NSAttributedString, options: ConversionOptions, title: String?, author: String?) throws -> Data {
        let pageW = CGFloat(options.pageWidth), pageH = CGFloat(options.pageHeight)
        let margin = CGFloat(options.marginPt)
        let footer = margin * 0.45
        let contentSize = CGSize(width: pageW - margin * 2, height: pageH - margin * 2)

        let storage = NSTextStorage(attributedString: attributed)
        let lm = NSLayoutManager()
        lm.usesFontLeading = true
        lm.allowsNonContiguousLayout = false
        storage.addLayoutManager(lm)

        // 逐页添加文本容器直到全部排完
        var containers: [NSTextContainer] = []
        var emptyStreak = 0
        let totalGlyphs = lm.numberOfGlyphs
        while containers.count < 10000 {
            let tc = NSTextContainer(size: contentSize)
            tc.lineFragmentPadding = 0
            lm.addTextContainer(tc)
            containers.append(tc)
            let range = lm.glyphRange(for: tc)
            if range.length == 0 { emptyStreak += 1 } else { emptyStreak = 0 }
            if NSMaxRange(range) >= totalGlyphs || emptyStreak > 3 { break }
        }
        // 去掉末尾的空页
        while containers.count > 1, lm.glyphRange(for: containers.last!).length == 0 {
            containers.removeLast()
        }

        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        var info: [CFString: Any] = [kCGPDFContextCreator: Platform.generator]
        if let t = title { info[kCGPDFContextTitle] = t }
        if let a = author { info[kCGPDFContextAuthor] = a }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw ConversionError.toolFailed(L.pdfContextFailed)
        }
        let total = containers.count
        let footerFont = AttributedBuilder.font(8.5)

        for (i, tc) in containers.enumerated() {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            // 翻转为左上角原点，与 TextKit 坐标一致
            ctx.translateBy(x: 0, y: pageH)
            ctx.scaleBy(x: 1, y: -1)
            let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc

            let range = lm.glyphRange(for: tc)
            let origin = CGPoint(x: margin, y: margin)
            if range.length > 0 {
                lm.drawBackground(forGlyphRange: range, at: origin)
                lm.drawGlyphs(forGlyphRange: range, at: origin)
            }
            // 页码
            if total > 1 {
                let s = NSAttributedString(string: "\(i + 1) / \(total)", attributes: [.font: footerFont, .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)])
                let sz = s.size()
                s.draw(at: CGPoint(x: (pageW - sz.width) / 2, y: pageH - footer - sz.height / 2))
            }
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

            // 超链接注释（PDF 坐标为左下角原点）
            if range.length > 0 {
                let charRange = lm.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                storage.enumerateAttribute(.link, in: charRange) { value, r, _ in
                    guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) else { return }
                    let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                    lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                        let pdfRect = CGRect(x: rect.minX + margin, y: pageH - (rect.maxY + margin), width: rect.width, height: rect.height)
                        ctx.setURL(url as CFURL, for: pdfRect)
                    }
                }
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
