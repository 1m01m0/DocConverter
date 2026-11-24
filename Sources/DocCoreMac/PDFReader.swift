import AppKit
import PDFKit
import Vision
import DocCore

// MARK: - PDF 读取
// 文字模式：按行提取文字及字号/位置，推断标题、段落、列表，去掉页眉页脚；没有文字层的页面用 Vision OCR 识别。
// 图片模式：每页渲染为一张图片（保留版式，不可编辑）。

public struct PDFInputFormat: DocumentReader {
    public var formats: [Format] { [.pdf] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        guard let pdf = PDFDocument(url: url) else { throw ConversionError.invalidFile(L.cannotOpenPDF) }
        if pdf.isLocked && !pdf.unlock(withPassword: "") { throw ConversionError.invalidFile(L.pdfEncrypted) }
        let title = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let author = pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        if options.pdfReadMode == .pageImages {
            return Document(title: title, author: author, blocks: pageImages(pdf, options: options))
        }
        var doc = PDFTextExtractor(pdf: pdf, options: options).extract()
        // 完全提取不到文字（扫描件且 OCR 不可用）时，退回整页图片，保证有输出
        if doc.blocks.isEmpty { doc.blocks = pageImages(pdf, options: options) }
        doc.title = title
        doc.author = author
        return doc
    }

    func pageImages(_ pdf: PDFDocument, options: ConversionOptions) -> [Block] {
        var blocks: [Block] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i), let cg = Rasterizer.render(page: page, dpi: options.imageDPI),
                  let data = Rasterizer.encode(cg, format: .jpg) else { continue }
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            blocks.append(.image(ImageData(data: data, mime: "image/jpeg", alt: L.pageN(i + 1))))
        }
        return blocks
    }
}

final class PDFTextExtractor {
    let pdf: PDFDocument
    let options: ConversionOptions

    struct Line {
        var page: Int
        var runs: [Run]
        var text: String
        var x: CGFloat, y: CGFloat          // y：距页面顶部
        var width: CGFloat, height: CGFloat
        var fontSize: CGFloat
        var bold: Bool
        var pageHeight: CGFloat
        var mono: Bool = false
        var column = 0              // 多栏页面中的栏序号
        var colX: CGFloat = -1      // 所在栏左边界（-1 表示单栏，用全局左边距）
        var colWidth: CGFloat = -1  // 所在栏宽度
    }

    init(pdf: PDFDocument, options: ConversionOptions) { self.pdf = pdf; self.options = options }

    func extract() -> Document {
        var lines: [Line] = []
        var pageWidths: [CGFloat] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)
            pageWidths.append(box.width)
            var pageLines = textLines(page: page, index: i, box: box)
            if pageLines.isEmpty && options.ocrScannedPages {
                pageLines = ocrLines(page: page, index: i, box: box)
            }
            lines.append(contentsOf: columnize(pageLines, pageWidth: box.width))
        }
        guard !lines.isEmpty else { return Document() }
        lines = removeHeadersFooters(lines)
        return Document(blocks: buildBlocks(lines))
    }

    // MARK: 行提取

    func textLines(page: PDFPage, index: Int, box: CGRect) -> [Line] {
        guard let sel = page.selection(for: box) else { return [] }
        var out: [Line] = []
        for ls in sel.selectionsByLine() {
            guard let raw = ls.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let b = ls.bounds(for: page)
            var runs: [Run] = []
            var maxSize: CGFloat = 0
            var boldChars = 0, totalChars = 0
            var monoChars = 0, latinChars = 0
            if let attr = ls.attributedString {
                attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { v, r, _ in
                    let s = (attr.string as NSString).substring(with: r)
                    guard let font = v as? NSFont else { runs.append(Run(s)); return }
                    let name = font.fontName.lowercased()
                    let isBold = font.fontDescriptor.symbolicTraits.contains(.bold) || name.contains("bold") || name.contains("heavy")
                        || name.contains("black") || name.contains("semibold") || name.hasSuffix("-w6") || name.hasSuffix("-w7")
                    let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || name.contains("italic") || name.contains("oblique")
                    let isMono = font.fontDescriptor.symbolicTraits.contains(.monoSpace) || name.contains("mono") || name.contains("courier") || name.contains("consolas") || name.contains("menlo")
                    let n = s.trimmingCharacters(in: .whitespaces).count
                    let latin = s.filter { !$0.isWhitespace && !TextUtil.isCJK($0) }.count
                    latinChars += latin
                    if isMono { monoChars += latin }
                    totalChars += n
                    if isBold { boldChars += n }
                    if n > 0 { maxSize = max(maxSize, font.pointSize) }
                    runs.append(Run(s, TextStyle(bold: isBold, italic: isItalic, code: isMono)))
                }
            }
            if runs.isEmpty { runs = [Run(raw)] }
            runs = runs.map { var r = $0; r.text = TextUtil.normalizeCJKRadicals(r.text.replacingOccurrences(of: "\n", with: "")); return r }.trimmed()
            let lineMono = monoChars > 0 && Double(monoChars) >= Double(latinChars) * 0.6
            let size = maxSize > 0 ? maxSize : b.height * 0.8
            let lineBold = totalChars > 0 && Double(boldChars) / Double(totalChars) > 0.8
            if lineBold { runs = runs.map { var r = $0; r.style.bold = false; return r } }
            out.append(Line(page: index, runs: runs, text: runs.plainText, x: b.minX - box.minX, y: box.maxY - b.maxY,
                            width: b.width, height: b.height, fontSize: size.rounded(toPlaces: 1), bold: lineBold, pageHeight: box.height,
                            mono: lineMono))
        }
        // 按阅读顺序排序：从上到下，同一行从左到右
        out.sort { abs($0.y - $1.y) > min($0.height, $1.height) * 0.5 ? $0.y < $1.y : $0.x < $1.x }
        return out
    }

    /// 扫描页：渲染后交给 Vision 识别（支持简繁中文与英文）
    func ocrLines(page: PDFPage, index: Int, box: CGRect) -> [Line] {
        guard let cg = Rasterizer.render(page: page, dpi: 200) else { return [] }
        // 先用精确模式；在没有神经网络引擎的环境（如虚拟机）里会失败，再退回快速模式
        var observations: [VNRecognizedTextObservation] = []
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                observations = request.results ?? []
                break
            } catch { continue }
        }
        var out: [Line] = []
        for obs in observations where obs.confidence >= 0.3 {
            guard let cand = obs.topCandidates(1).first else { continue }
            let r = obs.boundingBox   // 归一化，左下角原点
            let h = r.height * box.height
            let text = TextUtil.normalizeCJKRadicals(cand.string)
            out.append(Line(page: index, runs: [Run(text)], text: text, x: r.minX * box.width,
                            y: (1 - r.maxY) * box.height, width: r.width * box.width, height: h,
                            fontSize: (h * 0.8).rounded(toPlaces: 0), bold: false, pageHeight: box.height))
        }
        out.sort { abs($0.y - $1.y) > min($0.height, $1.height) * 0.5 ? $0.y < $1.y : $0.x < $1.x }
        return out
    }

    // MARK: 多栏版面

    /// 检测双栏页面：按"通栏内容（上）→ 左栏 → 右栏 → 通栏内容（下）"重新排序
    func columnize(_ lines: [Line], pageWidth: CGFloat) -> [Line] {
        guard lines.count >= 10 else { return lines }
        let mid = pageWidth / 2
        let gutter = pageWidth * 0.02
        var left: [Line] = [], right: [Line] = [], spanning: [Line] = []
        for l in lines {
            if l.x + l.width <= mid + gutter { left.append(l) }
            else if l.x >= mid - gutter { right.append(l) }
            else { spanning.append(l) }
        }
        // 两栏都要有足够多的行，并且在垂直方向上大面积重叠
        guard left.count >= 5, right.count >= 5 else { return lines }
        let lTop = left.map(\.y).min()!, lBottom = left.map { $0.y + $0.height }.max()!
        let rTop = right.map(\.y).min()!, rBottom = right.map { $0.y + $0.height }.max()!
        let overlap = min(lBottom, rBottom) - max(lTop, rTop)
        guard overlap > min(lBottom - lTop, rBottom - rTop) * 0.5 else { return lines }
        // 左右两侧在同一高度成对出现的行太多、且都很短 → 更像表格，不按分栏处理
        let avgLen = Double((left + right).map { $0.text.count }.reduce(0, +)) / Double(left.count + right.count)
        guard avgLen > 12 else { return lines }
        let top = max(lTop, rTop)
        func tag(_ ls: [Line], _ col: Int) -> [Line] {
            let x = ls.map(\.x).min() ?? 0
            let w = (ls.map { $0.x + $0.width }.max() ?? pageWidth) - x
            return ls.sorted { $0.y < $1.y }.map { var l = $0; l.column = col; l.colX = x; l.colWidth = w; return l }
        }
        let above = spanning.filter { $0.y < top }.sorted { $0.y < $1.y }
        let below = spanning.filter { $0.y >= top }.sorted { $0.y < $1.y }
        return above + tag(left, 1) + tag(right, 2) + below
    }

    // MARK: 页眉页脚

    func removeHeadersFooters(_ lines: [Line]) -> [Line] {
        let pages = Set(lines.map(\.page)).count
        func isMargin(_ l: Line) -> Bool { l.y < l.pageHeight * 0.08 || l.y + l.height > l.pageHeight * 0.92 }
        func normalized(_ s: String) -> String { s.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression) }
        var counts: [String: Int] = [:]
        if pages >= 3 {
            for l in lines where isMargin(l) { counts[normalized(l.text), default: 0] += 1 }
        }
        let pageNumber = #"^(第\s*)?[-–—]?\s*\d+\s*[-–—]?(\s*页)?(\s*/\s*(共\s*)?\d+\s*页?)?$|^(page\s*)?\d+(\s*(of|/)\s*\d+)?$"#
        return lines.filter { l in
            guard isMargin(l) else { return true }
            if l.text.lowercased().range(of: pageNumber, options: .regularExpression) != nil { return false }
            if pages >= 3, let c = counts[normalized(l.text)], c >= max(3, pages / 2) { return false }
            return true
        }
    }

    // MARK: 组装段落

    static let bulletChars: Set<Character> = ["•", "●", "○", "◦", "▪", "■", "□", "◆", "◇", "-", "–", "*", "·", "➢", "►", "✓", "√", "☐", "☑"]

    func listMarker(_ text: String) -> (ordered: Bool, number: Int, rest: String)? {
        if let f = text.first, PDFTextExtractor.bulletChars.contains(f) {
            let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty && (text.dropFirst().first == " " || (f != "-" && f != "*")) {
                return (false, 1, (f == "☐" || f == "☑") ? String(f) + " " + rest : rest)
            }
        }
        if let m = text.range(of: #"^(\d{1,3})[.、)）]\s*"#, options: .regularExpression) {
            let num = Int(text[m].filter(\.isNumber)) ?? 1
            let rest = String(text[m.upperBound...])
            if let f = rest.first, f.isNumber { return nil }   // "1.5 倍" 之类不是列表
            if !rest.isEmpty { return (true, num, rest) }
        }
        return nil
    }

    enum Item { case line(Line), table(Table, page: Int, y: CGFloat) }

    /// 把同一水平位置、彼此间隔较大的多段文字识别为表格
    func detectTables(_ lines: [Line], body: CGFloat) -> [Item] {
        // 1. 聚成"视觉行"
        var rows: [[Line]] = []
        for l in lines {
            if var last = rows.last, let f = last.first, f.page == l.page, f.column == l.column, abs(f.y - l.y) < min(f.height, l.height) * 0.6 {
                last.append(l); rows[rows.count - 1] = last
            } else { rows.append([l]) }
        }
        func cells(_ row: [Line]) -> [Line]? {
            let sorted = row.sorted { $0.x < $1.x }
            guard sorted.count >= 2 else { return nil }
            for i in 1..<sorted.count where sorted[i].x - (sorted[i - 1].x + sorted[i - 1].width) < body * 0.8 { return nil }
            return sorted
        }
        var items: [Item] = []
        var i = 0
        while i < rows.count {
            guard let first = cells(rows[i]) else {
                items.append(.line(rows[i].count == 1 ? rows[i][0] : merge(rows[i]))); i += 1; continue
            }
            // 收集连续的多列行
            var region: [[Line]] = [first]
            var j = i + 1
            while j < rows.count, let c = cells(rows[j]), let prev = region.last?.first, c[0].page == prev.page,
                  c[0].y - (prev.y + prev.height) < max(prev.height, c[0].height) * 2.5 {
                region.append(c); j += 1
            }
            // 列锚点：对所有单元格的左边界聚类
            let xs = region.flatMap { $0.map(\.x) }.sorted()
            var anchors: [CGFloat] = []
            for x in xs { if let l = anchors.last, x - l < body * 1.5 { continue }; anchors.append(x) }
            let avgLen = Double(region.flatMap { $0 }.map { $0.text.count }.reduce(0, +)) / Double(max(1, region.flatMap { $0 }.count))
            let isTable = region.count >= 2 && anchors.count >= 2 && (anchors.count >= 3 || avgLen <= 20)
            if !isTable {
                for r in region { items.append(.line(merge(r))) }
                i = j; continue
            }
            var grid: [[TableCell]] = []
            for r in region {
                var row = Array(repeating: [Run](), count: anchors.count)
                for c in r {
                    let col = anchors.enumerated().min { abs($0.element - c.x) < abs($1.element - c.x) }!.offset
                    if !row[col].isEmpty { row[col].append(Run(" ")) }
                    row[col].append(contentsOf: c.bold ? c.runs.map { var x = $0; x.style.bold = true; return x } : c.runs)
                }
                grid.append(row.map { TableCell($0.normalized()) })
            }
            // 表头行（整行加粗）不保留粗体标记
            if region[0].allSatisfy(\.bold) { grid[0] = grid[0].map { TableCell($0.content.map { var r = $0; r.style.bold = false; return r }) } }
            items.append(.table(Table(rows: grid, headerRows: 1), page: region[0][0].page, y: region[0][0].y))
            i = j
        }
        return items
    }

    func merge(_ row: [Line]) -> Line {
        let sorted = row.sorted { $0.x < $1.x }
        var m = sorted[0]
        for l in sorted.dropFirst() {
            m.runs.append(Run(" ")); m.runs.append(contentsOf: l.runs)
            m.width = l.x + l.width - m.x
            m.fontSize = max(m.fontSize, l.fontSize)
            m.bold = m.bold && l.bold
            m.mono = m.mono && l.mono
        }
        m.text = m.runs.plainText
        return m
    }

    func buildBlocks(_ lines: [Line]) -> [Block] {
        // 正文字号：按字符数加权的众数
        var sizeWeight: [CGFloat: Int] = [:]
        for l in lines { sizeWeight[l.fontSize, default: 0] += l.text.count }
        let body = sizeWeight.max { $0.value < $1.value }?.key ?? 11
        let headingSizes = Array(Set(lines.filter { $0.fontSize >= body * 1.15 && $0.text.count <= 60 }.map(\.fontSize))).sorted(by: >)
        func headingLevel(_ l: Line) -> Int? {
            if l.mono { return nil }
            guard l.fontSize >= body * 1.15, l.text.count <= 60 else {
                // 与正文同字号但整行加粗、较短、不以标点结尾：视作低级标题
                if l.bold, l.text.count <= 30, l.fontSize >= body * 0.98, !"。.;；:：,，".contains(l.text.last ?? " "),
                   listMarker(l.text) == nil { return min(headingSizes.count + 1, 4) }
                return nil
            }
            return min((headingSizes.firstIndex(of: l.fontSize) ?? 0) + 1, 4)
        }
        let bodyLines = lines.filter { abs($0.fontSize - body) < 0.6 }
        let maxBodyWidth: CGFloat = bodyLines.map(\.width).max() ?? 360
        let fullWidth: CGFloat = maxBodyWidth * 0.82
        let leftMargin: CGFloat = bodyLines.map(\.x).min() ?? 0

        var blocks: [Block] = []
        var para: [Run] = []
        var paraLast: Line? = nil
        var listItems: [(x: CGFloat, ordered: Bool, number: Int, runs: [Run])] = []
        var code: [Line] = []

        func flushPara() {
            let r = para.trimmed()
            if !r.isEmpty {
                if listItems.isEmpty { blocks.append(.paragraph(r)) }
                else { listItems[listItems.count - 1].runs = r }
            }
            para = []
        }
        func flushList() {
            flushPara()
            guard !listItems.isEmpty else { return }
            // 按标记的横向位置确定层级
            var levelsX: [CGFloat] = []
            for x in listItems.map(\.x).sorted() { if let l = levelsX.last, x - l < body * 0.8 { continue }; levelsX.append(x) }
            func level(_ x: CGFloat) -> Int { levelsX.enumerated().min { abs($0.element - x) < abs($1.element - x) }!.offset }
            blocks.append(contentsOf: nestList(listItems.map { (level($0.x), $0.ordered, $0.number, $0.runs) }[...]))
            listItems = []
        }
        func flushCode() {
            guard !code.isEmpty else { return }
            let minX = code.map(\.x).min() ?? 0
            let text = code.map { l -> String in
                let indent = max(0, Int(((l.x - minX) / (l.fontSize * 0.6)).rounded()))
                return String(repeating: " ", count: indent) + l.text
            }.joined(separator: "\n")
            blocks.append(.code(text: text, language: nil))
            code = []
        }
        func appendLine(_ l: Line) {
            if para.isEmpty { para = l.runs; return }
            let prev = para.plainText
            let joined = TextUtil.joinLines(prev, l.text)
            if joined.count < prev.count + l.text.count, let lastIdx = para.indices.last, para[lastIdx].text.hasSuffix("-") {
                para[lastIdx].text.removeLast()   // 连字符断词
            } else if joined.count > prev.count + l.text.count {
                para.append(Run(" "))
            }
            para.append(contentsOf: l.runs)
        }

        for item in detectTables(lines, body: body) {
            guard case .line(let l) = item else {
                if case .table(let t, _, _) = item { flushCode(); flushList(); flushPara(); blocks.append(.table(t)) }
                paraLast = nil
                continue
            }
            if l.mono {
                flushList(); flushPara()
                if let last = code.last, l.page == last.page, l.y - (last.y + last.height) > last.height * 1.2 { flushCode() }
                code.append(l); paraLast = nil
                continue
            }
            flushCode()
            if let lv = headingLevel(l) {
                if let last = blocks.last, case .heading(let plv, let c) = last, plv == lv, para.isEmpty, listItems.isEmpty,
                   let pl = paraLast, pl.page == l.page, l.y - (pl.y + pl.height) < l.height * 0.8, headingLevel(pl) == lv {
                    blocks[blocks.count - 1] = .heading(level: lv, content: [Run(TextUtil.joinLines(c.plainText, l.text))])
                } else {
                    flushList(); flushPara()
                    blocks.append(.heading(level: lv, content: [Run(l.text)]))
                }
                paraLast = l
                continue
            }
            if let m = listMarker(l.text) {
                flushPara()
                var runs = l.runs
                if let f = runs.first {
                    var t = f.text
                    if let r = t.range(of: #"^\s*(\d{1,3}[.、)）]|[•●○◦▪■◆◇\-–*·➢►✓√])\s*"#, options: .regularExpression) { t.removeSubrange(r) }
                    runs[0].text = t
                }
                listItems.append((l.x, m.ordered, m.number, []))
                para = runs.trimmed().isEmpty ? [Run(m.rest)] : runs
                paraLast = l
                continue
            }
            if let p = paraLast, !para.isEmpty {
                let gap = l.page == p.page ? l.y - (p.y + p.height) : 0
                let lineGap = max(p.height, l.height)
                let prevText = para.plainText
                let endsSentence = "。！？.!?:：;；”\"".contains(prevText.last ?? " ")
                let colFull = p.colWidth > 0 ? p.colWidth * 0.82 : fullWidth
                let prevShort = p.width < colFull && endsSentence
                let margin = l.colX >= 0 ? l.colX : leftMargin
                let indented = l.x > margin + body * 1.5 && l.x > p.x + body * 0.8
                let sizeChange = abs(l.fontSize - p.fontSize) > 0.8
                let newPage = l.page != p.page
                let breakPara = gap > lineGap * 0.9 || sizeChange || (indented && endsSentence) || (prevShort && !newPage) || (newPage && endsSentence)
                if !listItems.isEmpty {
                    // 列表项续行：比标记更靠右且间距正常
                    if !breakPara && l.x > (listItems.last?.x ?? 0) + body * 0.5 { appendLine(l); paraLast = l; continue }
                    flushList()
                } else if breakPara {
                    flushPara()
                }
            } else if !listItems.isEmpty {
                flushList()
            }
            appendLine(l)
            paraLast = l
        }
        flushCode()
        flushList()
        flushPara()
        return blocks
    }

    func nestList(_ items: ArraySlice<(Int, Bool, Int, [Run])>) -> [Block] {
        var out: [Block] = []
        var i = items.startIndex
        while i < items.endIndex {
            let base = items[i].0
            let ordered = items[i].1
            let start = items[i].2
            var group: [ListItem] = []
            while i < items.endIndex, items[i].0 >= base {
                if items[i].0 == base {
                    if items[i].1 != ordered && !group.isEmpty { break }
                    group.append(ListItem([.paragraph(items[i].3)])); i += 1
                } else {
                    var j = i
                    while j < items.endIndex, items[j].0 > base { j += 1 }
                    let nested = nestList(items[i..<j])
                    if group.isEmpty { group.append(ListItem([])) }
                    group[group.count - 1].blocks.append(contentsOf: nested)
                    i = j
                }
            }
            out.append(.list(ordered: ordered, start: start, items: group))
        }
        return out
    }
}

extension CGFloat {
    func rounded(toPlaces p: Int) -> CGFloat {
        let m = pow(10, CGFloat(p))
        return (self * m).rounded() / m
    }
}
