import AppKit
import DocCore

// MARK: - 中间表示 → NSAttributedString（用于 PDF / RTF / DOC / ODT 输出）

public final class AttributedBuilder {
    let options: ConversionOptions
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let base: CGFloat
    /// PDF 渲染时把分页写成换页符；RTF 等格式同样识别 \f
    let pageBreakChar = "\u{000C}"

    /// richText = true：输出 RTF/DOC/ODT 时不用 NSTextBlock 做装饰（这些格式会把装饰块存成表格）
    let richText: Bool

    public init(options: ConversionOptions, richText: Bool = false) {
        self.options = options
        self.richText = richText
        self.contentWidth = CGFloat(options.pageWidth - options.marginPt * 2)
        self.contentHeight = CGFloat(options.pageHeight - options.marginPt * 2)
        self.base = CGFloat(options.baseFontSize)
    }

    let textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    let mutedColor = NSColor(calibratedWhite: 0.38, alpha: 1)
    let linkColor = NSColor(calibratedRed: 0.02, green: 0.39, blue: 0.76, alpha: 1)
    let borderColor = NSColor(calibratedWhite: 0.78, alpha: 1)
    let codeBackground = NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.98, alpha: 1)

    // 使用公开字体名（冬青黑体 / Menlo），生成的 PDF、RTF、DOC 在其他软件里也能识别字体。
    // 不用苹方：苹方生成的 PDF 复制文字时部分汉字会变成康熙部首字符（如“⼀”“⻓”）。
    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let names = bold ? ["HiraginoSansGB-W6", "PingFangSC-Semibold"] : ["HiraginoSansGB-W3", "PingFangSC-Regular"]
        for n in names { if let f = NSFont(name: n, size: size) { return f } }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }
    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size) ?? NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    var bodyFont: NSFont { Self.font(base) }
    var monoFont: NSFont { Self.mono(base * 0.9) }

    func paragraphStyle(spacingBefore: CGFloat = 0, after: CGFloat? = nil, indent: CGFloat = 0, align: NSTextAlignment = .natural) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = base * 0.3
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = after ?? base * 0.6
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.alignment = align
        return p
    }

    public func build(_ doc: Document) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, b) in doc.blocks.enumerated() {
            append(b, to: out, indent: 0, quoteBlock: nil, isFirst: i == 0)
        }
        // 去掉末尾多余换行
        while out.length > 0, out.string.hasSuffix("\n\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    // MARK: 块

    func append(_ b: Block, to out: NSMutableAttributedString, indent: CGFloat, quoteBlock: NSTextBlock?, isFirst: Bool) {
        func withQuote(_ p: NSMutableParagraphStyle) -> NSMutableParagraphStyle {
            if let q = quoteBlock { p.textBlocks = [q] }
            return p
        }
        switch b {
        case .heading(let level, let c):
            let scale: [CGFloat] = [2.0, 1.6, 1.35, 1.18, 1.05, 1.0]
            let size = base * scale[max(1, min(6, level)) - 1]
            let font = Self.font(size, bold: true)
            let p = withQuote(paragraphStyle(spacingBefore: isFirst ? 0 : size * 0.9, after: size * 0.45, indent: indent))
            p.lineSpacing = size * 0.15
            let color = level <= 2 ? NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.39, alpha: 1) : textColor
            out.append(inline(c, font: font, color: color, paragraph: p))
            out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: p]))
            // 一、二级标题下加分隔线
            if level <= 2 && quoteBlock == nil && !richText { appendRule(to: out, thin: true) }

        case .paragraph(let c):
            let p = withQuote(paragraphStyle(indent: indent))
            out.append(inline(c, font: bodyFont, color: quoteBlock == nil ? textColor : mutedColor, paragraph: p))
            out.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: p]))

        case .list(let ordered, let start, let items):
            appendList(ordered: ordered, start: start, items: items, to: out, indent: indent, level: 0, quoteBlock: quoteBlock)

        case .table(let t):
            appendTable(t, to: out)

        case .code(let text, _) where richText:
            for line in text.components(separatedBy: "\n") {
                let p = paragraphStyle(after: 0, indent: indent + 12)
                p.lineSpacing = 1
                out.append(NSAttributedString(string: (line.isEmpty ? " " : line) + "\n",
                                              attributes: [.font: monoFont, .foregroundColor: textColor, .paragraphStyle: p]))
            }
            if let p = (paragraphStyle(after: base * 0.6, indent: indent + 12)) as NSParagraphStyle?, out.length > 0 {
                var r = NSRange(location: 0, length: 0)
                _ = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: &r)
                out.addAttribute(.paragraphStyle, value: p, range: r)
            }

        case .quote(let inner) where richText:
            for (i, ib) in inner.enumerated() { append(ib, to: out, indent: indent + 24, quoteBlock: nil, isFirst: i == 0) }

        case .horizontalRule where richText:
            let p = paragraphStyle(align: .center)
            out.append(NSAttributedString(string: String(repeating: "─", count: 24) + "\n", attributes: [.font: bodyFont, .foregroundColor: borderColor, .paragraphStyle: p]))

        case .code(let text, _):
            let block = NSTextBlock()
            block.backgroundColor = codeBackground
            block.setContentWidth(100, type: .percentageValueType)
            block.setWidth(8, type: .absoluteValueType, for: .padding)
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setBorderColor(NSColor(calibratedWhite: 0.88, alpha: 1))
            block.setWidth(base * 0.4, type: .absoluteValueType, for: .margin, edge: .maxY)
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let p = paragraphStyle(after: 0, indent: indent)
                p.lineSpacing = 1
                p.textBlocks = [block]
                p.lineBreakMode = .byCharWrapping
                out.append(NSAttributedString(string: (line.isEmpty ? " " : line) + "\n",
                                              attributes: [.font: monoFont, .foregroundColor: textColor, .paragraphStyle: p]))
            }

        case .quote(let inner):
            let block = NSTextBlock()
            block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
            block.setBorderColor(borderColor, for: .minX)
            block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
            block.setWidth(base * 0.4, type: .absoluteValueType, for: .margin, edge: .maxY)
            block.setContentWidth(100, type: .percentageValueType)
            for (i, ib) in inner.enumerated() { append(ib, to: out, indent: indent, quoteBlock: block, isFirst: i == 0) }

        case .image(let img):
            appendImage(img, to: out, indent: indent)

        case .horizontalRule:
            appendRule(to: out, thin: false)

        case .pageBreak:
            out.append(NSAttributedString(string: pageBreakChar, attributes: [.font: bodyFont]))
        }
    }

    func appendRule(to out: NSMutableAttributedString, thin: Bool) {
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(thin ? 0.5 : 0.8, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(thin ? NSColor(calibratedWhite: 0.85, alpha: 1) : borderColor, for: .maxY)
        let p = NSMutableParagraphStyle()
        p.textBlocks = [block]
        p.paragraphSpacing = thin ? base * 0.5 : base * 0.8
        p.maximumLineHeight = 2
        p.minimumLineHeight = 2
        out.append(NSAttributedString(string: "\n", attributes: [.font: Self.font(1), .paragraphStyle: p]))
    }

    func appendList(ordered: Bool, start: Int, items: [ListItem], to out: NSMutableAttributedString, indent: CGFloat, level: Int, quoteBlock: NSTextBlock?, parents: [NSTextList] = []) {
        let markerFormats: [NSTextList.MarkerFormat] = ordered ? [.decimal, .lowercaseAlpha, .lowercaseRoman] : [.disc, .circle, .square]
        let list = NSTextList(markerFormat: markerFormats[level % 3], options: 0)
        list.startingItemNumber = start
        let step = base * 1.8
        let left = indent + step * CGFloat(level)
        for (i, item) in items.enumerated() {
            var first = true
            for b in item.blocks {
                switch b {
                case .paragraph(let c):
                    let p = paragraphStyle(after: base * 0.25, indent: left + step)
                    p.firstLineHeadIndent = left
                    p.tabStops = [NSTextTab(textAlignment: .left, location: left + step * 0.15), NSTextTab(textAlignment: .left, location: left + step)]
                    p.defaultTabInterval = step
                    p.textLists = parents + [list]   // 完整的嵌套链，RTF/DOC 才能保留层级
                    if let q = quoteBlock { p.textBlocks = [q] }
                    var marker = ""
                    if first {
                        let m: String
                        if ordered { m = list.marker(forItemNumber: start + i) + "." }
                        else { m = ["•", "◦", "▪"][level % 3] }
                        marker = "\t\(m)\t"
                        if let ch = item.checked { marker += ch ? "☑ " : "☐ " }
                    } else {
                        p.firstLineHeadIndent = left + step
                    }
                    let para = NSMutableAttributedString(string: marker, attributes: [.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: p])
                    para.append(inline(c, font: bodyFont, color: textColor, paragraph: p))
                    para.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: p]))
                    out.append(para)
                    first = false
                case .list(let o, let s, let sub):
                    appendList(ordered: o, start: s, items: sub, to: out, indent: indent, level: level + 1, quoteBlock: quoteBlock, parents: parents + [list])
                default:
                    append(b, to: out, indent: left + step, quoteBlock: quoteBlock, isFirst: false)
                }
            }
        }
        // 列表结束后补一点间距
        if level == 0, out.length > 0,
           let p = (out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            p.paragraphSpacing = base * 0.6
            var r = NSRange(location: 0, length: 0)
            _ = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: &r)
            out.addAttribute(.paragraphStyle, value: p, range: r)
        }
    }

    func appendTable(_ t: Table, to out: NSMutableAttributedString) {
        let t = t.padded()
        guard t.columnCount > 0 else { return }
        let table = NSTextTable()
        table.numberOfColumns = t.columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        table.setWidth(base * 0.6, type: .absoluteValueType, for: .margin, edge: .maxY)
        let cellFont = Self.font(base * 0.92)
        let headFont = Self.font(base * 0.92, bold: true)
        for (ri, row) in t.rows.enumerated() {
            let header = ri < t.headerRows
            for (ci, cell) in row.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: ri, rowSpan: 1, startingColumn: ci, columnSpan: 1)
                block.setWidth(0.6, type: .absoluteValueType, for: .border)
                block.setBorderColor(borderColor)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                block.setWidth(6, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxX)
                if header { block.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1) }
                block.verticalAlignment = .topAlignment
                let p = NSMutableParagraphStyle()
                p.textBlocks = [block]
                p.lineSpacing = 1
                p.paragraphSpacing = 0
                let content = cell.content.isEmpty ? [Run(" ")] : cell.content
                let s = NSMutableAttributedString(attributedString: inline(content, font: header ? headFont : cellFont, color: textColor, paragraph: p))
                s.append(NSAttributedString(string: "\n", attributes: [.font: cellFont, .paragraphStyle: p]))
                out.append(s)
            }
        }
    }

    func appendImage(_ img: ImageData, to out: NSMutableAttributedString, indent: CGFloat) {
        guard let image = NSImage(data: img.data), image.size.width > 0 else {
            out.append(NSAttributedString(string: L.imagePlaceholder(img.alt) + "\n", attributes: [.font: bodyFont, .foregroundColor: mutedColor]))
            return
        }
        // 以像素尺寸 @96dpi 为自然大小，并限制在版心内
        var size = img.pixelWidth > 0 ? CGSize(width: CGFloat(img.pixelWidth) * 0.75, height: CGFloat(img.pixelHeight) * 0.75) : image.size
        let maxW = contentWidth - indent
        let maxH = contentHeight * 0.92
        let scale = min(1, maxW / size.width, maxH / size.height)
        size = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let att = NSTextAttachment()
        image.size = size
        att.image = image
        att.bounds = CGRect(origin: .zero, size: size)
        let p = paragraphStyle(spacingBefore: base * 0.3, after: base * 0.6, indent: indent, align: .center)
        let s = NSMutableAttributedString(attachment: att)
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
        out.append(s)
        out.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: p]))
    }

    // MARK: 行内

    func inline(_ runs: Inlines, font: NSFont, color: NSColor, paragraph: NSParagraphStyle) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let fm = NSFontManager.shared
        for r in runs.normalized() {
            var f = font
            if r.style.code { f = Self.mono(font.pointSize * 0.92) }
            if r.style.bold { f = r.style.code ? (NSFont(name: "Menlo-Bold", size: f.pointSize) ?? f) : Self.font(f.pointSize, bold: true) }
            if r.style.italic {
                let it = fm.convert(f, toHaveTrait: .italicFontMask)
                f = it
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: paragraph]
            if r.style.italic && !fm.traits(of: f).contains(.italicFontMask) {
                attrs[.obliqueness] = 0.18   // 系统字体（含中文）没有斜体字形时模拟倾斜
            }
            if r.style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if r.style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if r.style.code { attrs[.backgroundColor] = NSColor(calibratedWhite: 0.94, alpha: 1); attrs[.foregroundColor] = NSColor(calibratedRed: 0.72, green: 0.15, blue: 0.3, alpha: 1) }
            if let l = r.style.link, let url = URL(string: l) ?? URL(string: l.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
                attrs[.link] = url
                attrs[.foregroundColor] = linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: r.text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: attrs))
        }
        return out
    }
}
