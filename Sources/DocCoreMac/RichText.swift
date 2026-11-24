import AppKit
import DocCore

// MARK: - RTF / Word 97 (.doc) / OpenDocument (.odt)：借助系统 NSAttributedString 读写

public struct RichTextFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.rtf, .doc, .odt] }
    public init() {}

    static func docType(_ f: Format) -> NSAttributedString.DocumentType {
        switch f {
        case .doc: return .docFormat
        case .odt: return .openDocument
        default: return .rtf
        }
    }

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        var attrs: NSDictionary? = nil
        let s: NSAttributedString
        do {
            s = try NSAttributedString(url: url, options: [.documentType: RichTextFormat.docType(format)], documentAttributes: &attrs)
        } catch {
            // .doc 文件有时其实是 RTF 或 HTML
            do { s = try NSAttributedString(url: url, options: [:], documentAttributes: &attrs) }
            catch { throw ConversionError.invalidFile(L.systemCannotParse(format.displayName)) }
        }
        var doc = Document(blocks: AttributedParser().parse(s))
        doc.title = (attrs?[NSAttributedString.DocumentAttributeKey.title] as? String).flatMap { $0.isEmpty ? nil : $0 }
        doc.author = attrs?[NSAttributedString.DocumentAttributeKey.author] as? String
        return doc
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let attr = AttributedBuilder(options: options, richText: true).build(doc)
        var docAttrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: RichTextFormat.docType(format),
            .paperSize: NSSize(width: options.pageWidth, height: options.pageHeight),
            .leftMargin: options.marginPt, .rightMargin: options.marginPt,
            .topMargin: options.marginPt, .bottomMargin: options.marginPt,
        ]
        if let t = doc.effectiveTitle { docAttrs[.title] = t }
        if let a = doc.author { docAttrs[.author] = a }
        let data = try attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: docAttrs)
        try data.write(to: url)
        return [url]
    }
}

// MARK: NSAttributedString → 中间表示

final class AttributedParser {
    struct Para {
        var runs: [Run]
        var images: [ImageData]
        var fontSize: CGFloat
        var allMono: Bool
        var listLevel: Int?
        var ordered: Bool
        var cell: (table: NSTextTable, row: Int, col: Int)?
        var pageBreakBefore: Bool
        var indent: CGFloat = 0
    }

    func parse(_ s: NSAttributedString) -> [Block] {
        let ns = s.string as NSString
        var paras: [Para] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            // 段内的换页符拆成多个段落
            var start = range.location
            var pageBreak = false
            for i in range.location..<NSMaxRange(range) where ns.character(at: i) == 0x0C {
                if i > start { paras.append(self.para(s, NSRange(location: start, length: i - start), pageBreak: pageBreak)) }
                pageBreak = true
                start = i + 1
            }
            let rest = NSRange(location: start, length: NSMaxRange(range) - start)
            paras.append(self.para(s, rest, pageBreak: pageBreak))
        }

        // 正文字号
        var weight: [CGFloat: Int] = [:]
        for p in paras { weight[p.fontSize, default: 0] += p.runs.plainText.count }
        let body = weight.max { $0.value < $1.value }?.key ?? 12
        let headingSizes = Array(Set(paras.filter { $0.listLevel == nil && $0.fontSize >= body * 1.15 && !$0.runs.isBlank && $0.runs.plainText.count < 100 }
            .map(\.fontSize))).sorted(by: >)

        var blocks: [Block] = []
        var listBuf: [(level: Int, ordered: Bool, runs: [Run], indent: CGFloat)] = []
        var codeBuf: [String] = []
        var table: NSTextTable? = nil
        var tableParas: [Para] = []

        func flushList() {
            guard !listBuf.isEmpty else { return }
            // 没有列表元数据（level == -1）时按缩进量排序推断层级
            if listBuf.contains(where: { $0.level < 0 }) {
                var levels: [CGFloat] = []
                for x in listBuf.map(\.indent).sorted() { if let l = levels.last, x - l < 6 { continue }; levels.append(x) }
                for i in listBuf.indices {
                    let x = listBuf[i].indent
                    listBuf[i].level = levels.enumerated().min { abs($0.element - x) < abs($1.element - x) }?.offset ?? 0
                }
            }
            blocks.append(contentsOf: buildList(listBuf.map { ($0.level, $0.ordered, $0.runs) }[...]))
            listBuf = []
        }
        func flushCode() {
            if !codeBuf.isEmpty { blocks.append(.code(text: codeBuf.joined(separator: "\n"), language: nil)); codeBuf = [] }
        }

        func processNonCell(_ p: Para) {
            if let lv = p.listLevel {
                flushCode()
                if !p.runs.isBlank { listBuf.append((lv, p.ordered, p.runs.trimmed(), p.indent)) }
                return
            }
            if p.allMono && !p.runs.isBlank || (p.allMono && !codeBuf.isEmpty && p.runs.isBlank) {
                flushList()
                codeBuf.append(p.runs.plainText)
                return
            }
            flushList(); flushCode()
            if p.runs.isBlank {
                blocks.append(contentsOf: p.images.map { .image($0) })
                return
            }
            let text = p.runs.trimmed()
            if p.fontSize >= body * 1.15, text.plainText.count < 100, let idx = headingSizes.firstIndex(of: p.fontSize) {
                blocks.append(.heading(level: min(idx + 1, 6), content: text.map { var r = $0; r.style.bold = false; return r }.normalized()))
            } else {
                blocks.append(.paragraph(text))
            }
            blocks.append(contentsOf: p.images.map { .image($0) })
        }

        func flushTable() {
            guard table != nil else { return }
            let ps = tableParas
            table = nil; tableParas = []
            let cols = (ps.compactMap { $0.cell?.col }.max() ?? 0) + 1
            if cols <= 1 {
                // 单列"表格"通常是 RTF 里的装饰块（代码底色、引用边框、分隔线），按普通段落处理
                for var q in ps { q.cell = nil; processNonCell(q) }
                return
            }
            var cells: [Int: [Int: [Run]]] = [:]
            for q in ps {
                guard let c = q.cell else { continue }
                var existing = cells[c.row]?[c.col] ?? []
                if !existing.isEmpty { existing.append(Run("\n")) }
                existing.append(contentsOf: q.runs)
                cells[c.row, default: [:]][c.col] = existing
            }
            let rows = (cells.keys.max() ?? -1) + 1
            if rows > 0 {
                var grid = (0..<rows).map { r in (0..<cols).map { c in TableCell((cells[r]?[c] ?? []).trimmed()) } }
                // 表头整行加粗时去掉粗体标记（表头本身已表达强调）
                if rows > 1, grid[0].allSatisfy({ $0.content.allSatisfy { $0.style.bold || $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }) {
                    grid[0] = grid[0].map { TableCell($0.content.map { var r = $0; r.style.bold = false; return r }) }
                }
                blocks.append(.table(Table(rows: grid, headerRows: rows > 1 ? 1 : 0)))
            }
        }

        for p in paras {
            if p.pageBreakBefore { flushList(); flushCode(); flushTable(); blocks.append(.pageBreak) }
            if let c = p.cell {
                flushList(); flushCode()
                if table !== c.table { flushTable(); table = c.table }
                tableParas.append(p)
                continue
            }
            flushTable()
            processNonCell(p)
        }
        flushList(); flushCode(); flushTable()
        return blocks
    }

    func buildList(_ items: ArraySlice<(level: Int, ordered: Bool, runs: [Run])>) -> [Block] {
        guard let first = items.first else { return [] }
        let base = first.level
        var result: [Block] = []
        var listItems: [ListItem] = []
        var ordered = first.ordered
        var i = items.startIndex
        while i < items.endIndex {
            if items[i].level <= base {
                // 同级里有序/无序切换时拆成两个列表
                if items[i].ordered != ordered && !listItems.isEmpty {
                    result.append(.list(ordered: ordered, start: 1, items: listItems))
                    listItems = []
                }
                ordered = items[i].ordered
                listItems.append(ListItem([.paragraph(items[i].runs)])); i += 1
            } else {
                var j = i
                while j < items.endIndex, items[j].level > base { j += 1 }
                let nested = buildList(items[i..<j])
                if listItems.isEmpty { listItems.append(ListItem([])) }
                listItems[listItems.count - 1].blocks.append(contentsOf: nested)
                i = j
            }
        }
        if !listItems.isEmpty { result.append(.list(ordered: ordered, start: 1, items: listItems)) }
        return result
    }

    func para(_ s: NSAttributedString, _ range: NSRange, pageBreak: Bool) -> Para {
        let loc = min(range.location, max(0, s.length - 1))
        let ps = s.length > 0 ? s.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle : nil
        var runs: [Run] = []
        var images: [ImageData] = []
        var maxSize: CGFloat = 0
        var allMono = range.length > 0
        let fm = NSFontManager.shared
        if range.length > 0 {
            s.enumerateAttributes(in: range) { attrs, r, _ in
                var text = (s.string as NSString).substring(with: r)
                if let att = attrs[.attachment] as? NSTextAttachment {
                    if let img = AttributedParser.image(from: att) { images.append(img) }
                    text = text.replacingOccurrences(of: "\u{FFFC}", with: "")
                    if text.isEmpty { return }
                }
                var st = TextStyle()
                if let f = attrs[.font] as? NSFont {
                    let traits = fm.traits(of: f)
                    st.bold = traits.contains(.boldFontMask)
                    st.italic = traits.contains(.italicFontMask) || ((attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0.05
                    let mono = traits.contains(.fixedPitchFontMask) || f.fontName.lowercased().contains("mono") || f.fontName.lowercased().contains("courier") || f.fontName.lowercased().contains("menlo")
                    st.code = mono
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        maxSize = max(maxSize, f.pointSize)
                        if !mono { allMono = false }
                    }
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty { allMono = false }
                if let u = attrs[.underlineStyle] as? NSNumber, u.intValue != 0 { st.underline = true }
                if let k = attrs[.strikethroughStyle] as? NSNumber, k.intValue != 0 { st.strike = true }
                if let l = attrs[.link] { st.link = (l as? URL)?.absoluteString ?? (l as? String); st.underline = false }
                runs.append(Run(text.replacingOccurrences(of: "\u{2028}", with: "\n"), st))
            }
        }
        if allMono { runs = runs.map { var r = $0; r.style.code = false; return r } }
        var listLevel: Int? = nil
        var ordered = false
        if let lists = ps?.textLists, let last = lists.last {
            listLevel = lists.count - 1
            let fmt = last.markerFormat.rawValue.lowercased()
            ordered = fmt.contains("decimal") || fmt.contains("alpha") || fmt.contains("roman") || fmt.contains("octal") || fmt.contains("hex")
            // 去掉文本里的列表标记 "\t•\t" / "\t1.\t"
            if var f = runs.first {
                if let r = f.text.range(of: #"^\t?[^\t]{0,12}\t"#, options: .regularExpression) { f.text.removeSubrange(r) }
                runs[0] = f
            }
        }
        // 没有 NSTextList 元数据时，按 "\t•\t" / "1.\t" 这类前缀识别列表
        if listLevel == nil, let f = runs.first,
           let r = f.text.range(of: #"^\t?([•◦▪●■□–\-]|\d{1,3}[.)])\t"#, options: .regularExpression) {
            let marker = f.text[r].trimmingCharacters(in: .whitespaces)
            ordered = marker.first?.isNumber ?? false
            listLevel = -1
            runs[0].text.removeSubrange(r)
        }
        var cell: (NSTextTable, Int, Int)? = nil
        if let tb = ps?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).last {
            cell = (tb.table, tb.startingRow, tb.startingColumn)
        }
        return Para(runs: runs.normalized(), images: images, fontSize: maxSize.rounded(), allMono: allMono && !runs.isBlank,
                    listLevel: listLevel, ordered: ordered, cell: cell, pageBreakBefore: pageBreak, indent: ps?.headIndent ?? 0)
    }

    static func image(from att: NSTextAttachment) -> ImageData? {
        if let d = att.fileWrapper?.regularFileContents, ImageInfo.detect(d) != nil {
            return ImageData(data: d, alt: att.fileWrapper?.preferredFilename ?? "")
        }
        if let d = att.contents, ImageInfo.detect(d) != nil { return ImageData(data: d) }
        if let img = att.image, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return ImageData(data: png, mime: "image/png")
        }
        return nil
    }
}

// MARK: - LibreOffice 高保真转换（可选，检测到安装时启用）

public struct LibreOfficeConverter: DirectConverter {
    public var name: String { "LibreOffice" }
    public init() {}

    public static var executable: URL? {
        let fm = FileManager.default
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            NSHomeDirectory() + "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public static var isAvailable: Bool { executable != nil }

    static let sources: Set<Format> = [.docx, .doc, .pptx, .xlsx, .odt, .rtf]

    public func canConvert(from: Format, to: Format, options: ConversionOptions) -> Bool {
        guard options.useLibreOffice, LibreOfficeConverter.isAvailable else { return false }
        if to == .pdf { return LibreOfficeConverter.sources.contains(from) }
        // Word 新旧格式互转
        return [.docx, .doc, .odt, .rtf].contains(from) && [.docx, .doc, .odt].contains(to)
    }

    public func convert(_ input: URL, from: Format, to: Format, output: URL, options: ConversionOptions) throws -> [URL] {
        guard let exe = LibreOfficeConverter.executable else { throw ConversionError.toolFailed(L.libreOfficeNotFound) }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("docconv-lo-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let profile = tmp.appendingPathComponent("profile", isDirectory: true)
        let p = Process()
        p.executableURL = exe
        p.arguments = ["-env:UserInstallation=\(profile.absoluteString)", "--headless", "--norestore", "--nologo",
                       "--convert-to", to.fileExtension, "--outdir", tmp.path, input.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        let deadline = Date().addingTimeInterval(300)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.terminate(); throw ConversionError.toolFailed(L.libreOfficeTimeout) }
        let produced = tmp.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension(to.fileExtension)
        guard fm.fileExists(atPath: produced.path) else { throw ConversionError.toolFailed(L.libreOfficeNoOutput(p.terminationStatus)) }
        try fm.moveItem(at: produced, to: output)
        return [output]
    }
}
