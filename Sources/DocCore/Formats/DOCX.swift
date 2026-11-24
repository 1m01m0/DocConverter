import Foundation

// MARK: - Word (.docx)

public struct DOCXFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.docx] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let zip = try ZipArchive(url: url)
        return try DOCXReader(zip: zip).read()
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let data = DOCXWriter(options: options).build(doc)
        try data.write(to: url)
        return [url]
    }
}

// MARK: 读取

final class DOCXReader {
    let zip: ZipArchive
    var docPath = "word/document.xml"
    var rels = Relationships()

    struct StyleInfo { var name: String; var basedOn: String?; var outline: Int?; var numId: String?; var ilvl: Int? }
    var styles: [String: StyleInfo] = [:]
    var numFormats: [String: [Int: String]] = [:]   // numId -> ilvl -> numFmt
    var numStarts: [String: [Int: Int]] = [:]

    init(zip: ZipArchive) { self.zip = zip }

    func read() throws -> Document {
        let pkgRels = Relationships(zip: zip, partPath: "")
        if let main = pkgRels.first(typeSuffix: "/officeDocument") { docPath = main }
        guard let data = zip.read(docPath), let root = XML.parse(data), root.name == "w:document" else {
            throw ConversionError.invalidFile(L.missingPart("word/document.xml"))
        }
        rels = Relationships(zip: zip, partPath: docPath)
        loadStyles()
        loadNumbering()
        guard let body = root.first("w:body") else { return Document() }
        var doc = Document(blocks: parseBody(body.elements))
        if let core = zip.read("docProps/core.xml").flatMap({ XML.parse($0) }) {
            let t = core.first("dc:title")?.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if let t = t, !t.isEmpty { doc.title = t }
            doc.author = core.first("dc:creator")?.textContent
        }
        return doc
    }

    func loadStyles() {
        guard let p = rels.first(typeSuffix: "/styles"), let d = zip.read(p), let root = XML.parse(d) else { return }
        for s in root.children("w:style") {
            guard let id = s["w:styleId"] ?? s["styleId"] else { continue }
            let name = s.child("w:name")?["w:val"] ?? s.child("w:name")?["val"] ?? id
            let basedOn = s.child("w:basedOn").flatMap { $0["w:val"] ?? $0["val"] }
            let outline = s.path("w:pPr", "w:outlineLvl").flatMap { $0["w:val"] ?? $0["val"] }.flatMap { Int($0) }
            let numPr = s.path("w:pPr", "w:numPr")
            let numId = numPr?.child("w:numId").flatMap { $0["w:val"] ?? $0["val"] }
            let ilvl = numPr?.child("w:ilvl").flatMap { $0["w:val"] ?? $0["val"] }.flatMap { Int($0) }
            styles[id] = StyleInfo(name: name, basedOn: basedOn, outline: outline, numId: numId, ilvl: ilvl)
        }
    }

    func loadNumbering() {
        guard let p = rels.first(typeSuffix: "/numbering"), let d = zip.read(p), let root = XML.parse(d) else { return }
        var abstract: [String: [Int: String]] = [:]
        var abstractStart: [String: [Int: Int]] = [:]
        for a in root.children("w:abstractNum") {
            guard let aid = a["w:abstractNumId"] ?? a["abstractNumId"] else { continue }
            var lv: [Int: String] = [:]
            var st: [Int: Int] = [:]
            for l in a.children("w:lvl") {
                let il = Int(l["w:ilvl"] ?? l["ilvl"] ?? "0") ?? 0
                lv[il] = l.child("w:numFmt").flatMap { $0["w:val"] ?? $0["val"] } ?? "decimal"
                st[il] = l.child("w:start").flatMap { $0["w:val"] ?? $0["val"] }.flatMap { Int($0) } ?? 1
            }
            abstract[aid] = lv
            abstractStart[aid] = st
        }
        for n in root.children("w:num") {
            guard let nid = n["w:numId"] ?? n["numId"], let aid = n.child("w:abstractNumId").flatMap({ $0["w:val"] ?? $0["val"] }) else { continue }
            numFormats[nid] = abstract[aid] ?? [:]
            var st = abstractStart[aid] ?? [:]
            for o in n.children("w:lvlOverride") {
                if let il = Int(o["w:ilvl"] ?? o["ilvl"] ?? ""), let s = o.child("w:startOverride").flatMap({ $0["w:val"] ?? $0["val"] }).flatMap({ Int($0) }) {
                    st[il] = s
                }
            }
            numStarts[nid] = st
        }
    }

    // 段落分类

    enum Kind: Equatable { case normal, heading(Int), list(numId: String, level: Int, ordered: Bool), code, quote, title }

    func styleChain(_ id: String?) -> [StyleInfo] {
        var out: [StyleInfo] = []
        var cur = id
        var guardCount = 0
        while let c = cur, let s = styles[c], guardCount < 10 { out.append(s); cur = s.basedOn; guardCount += 1 }
        return out
    }

    func classify(_ p: XNode) -> Kind {
        let pPr = p.child("w:pPr")
        let styleId = pPr?.child("w:pStyle").flatMap { $0["w:val"] ?? $0["val"] }
        let chain = styleChain(styleId)
        let names = chain.map { $0.name.lowercased() } + [styleId?.lowercased() ?? ""]

        // 直接编号 / 样式编号
        var numId = pPr?.path("w:numPr", "w:numId").flatMap { $0["w:val"] ?? $0["val"] }
        var ilvl = pPr?.path("w:numPr", "w:ilvl").flatMap { $0["w:val"] ?? $0["val"] }.flatMap { Int($0) }
        if numId == nil { for s in chain where s.numId != nil { numId = s.numId; ilvl = ilvl ?? s.ilvl; break } }

        for n in names {
            if n == "title" || n == "标题" { return .heading(1) }
            for prefix in ["heading ", "heading", "标题 ", "标题"] where n.hasPrefix(prefix) {
                if let lv = Int(n.dropFirst(prefix.count)), (1...9).contains(lv) { return .heading(min(lv, 6)) }
            }
        }
        if let ol = pPr?.child("w:outlineLvl").flatMap({ $0["w:val"] ?? $0["val"] }).flatMap({ Int($0) }) ?? chain.compactMap(\.outline).first,
           ol < 9 { return .heading(min(ol + 1, 6)) }

        // "List Bullet 2" / "List Number 3" 这类样式名自带层级
        var styleLevel = 0
        if let n = names.first(where: { $0.hasPrefix("list bullet") || $0.hasPrefix("list number") }), let d = Int(n.split(separator: " ").last ?? "") {
            styleLevel = max(0, d - 1)
        }
        if let nid = numId, nid != "0" {
            let lvl = max(ilvl ?? 0, styleLevel)
            let fmt = numFormats[nid]?[lvl] ?? "bullet"
            return .list(numId: nid, level: lvl, ordered: fmt != "bullet" && fmt != "none")
        }
        if names.contains(where: { $0.contains("code") || $0.contains("preformatted") || $0 == "源代码" }) { return .code }
        if names.contains(where: { $0.contains("quote") || $0 == "block text" || $0.contains("引用") }) { return .quote }
        if names.contains(where: { $0.hasPrefix("list bullet") }) { return .list(numId: "_bullet", level: styleLevel, ordered: false) }
        if names.contains(where: { $0.hasPrefix("list number") }) { return .list(numId: "_number", level: styleLevel, ordered: true) }
        return .normal
    }

    // 主体

    struct PendingListItem { var level: Int; var ordered: Bool; var numId: String; var blocks: [Block] }

    func parseBody(_ elements: [XNode]) -> [Block] {
        var blocks: [Block] = []
        var listItems: [PendingListItem] = []
        var codeLines: [String] = []
        var quoteBlocks: [Block] = []

        func flushList() {
            if !listItems.isEmpty {
                blocks.append(contentsOf: buildLists(listItems))
                listItems = []
            }
        }
        func flushCode() {
            if !codeLines.isEmpty { blocks.append(.code(text: codeLines.joined(separator: "\n"), language: nil)); codeLines = [] }
        }
        func flushQuote() {
            if !quoteBlocks.isEmpty { blocks.append(.quote(quoteBlocks)); quoteBlocks = [] }
        }
        func flushAll() { flushList(); flushCode(); flushQuote() }

        for el in expand(elements) {
            switch el.name {
            case "w:p":
                let kind = classify(el)
                let (runs, images, breakBefore, breakAfter) = paragraphContent(el)
                if breakBefore { flushAll(); blocks.append(.pageBreak) }
                switch kind {
                case .list(let numId, let level, let ordered):
                    flushCode(); flushQuote()
                    var bs: [Block] = []
                    if !runs.isBlank { bs.append(.paragraph(runs.trimmed())) }
                    bs.append(contentsOf: images.map { .image($0) })
                    if !bs.isEmpty { listItems.append(PendingListItem(level: level, ordered: ordered, numId: numId, blocks: bs)) }
                case .code:
                    flushList(); flushQuote()
                    codeLines.append(runs.plainText)
                case .quote:
                    flushList(); flushCode()
                    if !runs.isBlank { quoteBlocks.append(.paragraph(runs.trimmed())) }
                    quoteBlocks.append(contentsOf: images.map { .image($0) })
                case .heading(let lv):
                    flushAll()
                    if !runs.isBlank { blocks.append(.heading(level: lv, content: runs.trimmed().map { var r = $0; r.style.bold = false; return r }.normalized())) }
                    blocks.append(contentsOf: images.map { .image($0) })
                default:
                    // 空段落（图片除外）会打断列表，但 Word 中列表项之间常有空段落，这里宽松处理
                    if runs.isBlank && images.isEmpty {
                        if !codeLines.isEmpty { codeLines.append("") }
                        continue
                    }
                    flushAll()
                    if !runs.isBlank { blocks.append(.paragraph(runs.trimmed())) }
                    blocks.append(contentsOf: images.map { .image($0) })
                }
                if breakAfter { flushAll(); blocks.append(.pageBreak) }
            case "w:tbl":
                flushAll()
                if let t = parseTable(el) { blocks.append(.table(t)) }
            default:
                break
            }
        }
        flushAll()
        // 去掉代码块末尾空行、去掉开头/结尾的分页
        while let f = blocks.first, f == .pageBreak { blocks.removeFirst() }
        while let l = blocks.last, l == .pageBreak { blocks.removeLast() }
        return blocks.map { b in
            if case .code(let t, let l) = b { return .code(text: t.trimmingCharacters(in: .newlines), language: l) }
            return b
        }
    }

    /// 展开内容控件、自定义 XML、修订插入等包装元素
    func expand(_ els: [XNode]) -> [XNode] {
        var out: [XNode] = []
        for e in els {
            switch e.name {
            case "w:sdt": out.append(contentsOf: expand(e.child("w:sdtContent")?.elements ?? []))
            case "w:customXml", "w:ins", "w:smartTag": out.append(contentsOf: expand(e.elements))
            case "mc:AlternateContent":
                if let c = e.child("mc:Choice") ?? e.child("mc:Fallback") { out.append(contentsOf: expand(c.elements)) }
            default: out.append(e)
            }
        }
        return out
    }

    /// 按层级把扁平的列表项组装成嵌套列表
    func buildLists(_ items: [PendingListItem]) -> [Block] {
        var result: [Block] = []
        var i = 0
        while i < items.count {
            let base = items[i].level
            let ordered = items[i].ordered
            let numId = items[i].numId
            var group: [ListItem] = []
            while i < items.count, items[i].level >= base {
                if items[i].level == base {
                    if items[i].ordered != ordered && !group.isEmpty { break }
                    group.append(ListItem(items[i].blocks))
                    i += 1
                } else {
                    // 更深层级：收集子项
                    var j = i
                    while j < items.count, items[j].level > base { j += 1 }
                    let nested = buildLists(Array(items[i..<j]))
                    if group.isEmpty { group.append(ListItem([])) }
                    group[group.count - 1].blocks.append(contentsOf: nested)
                    i = j
                }
            }
            let start = numStarts[numId]?[base] ?? 1
            result.append(.list(ordered: ordered, start: start, items: group))
        }
        return result
    }

    // 段落内容

    func paragraphContent(_ p: XNode) -> (Inlines, [ImageData], Bool, Bool) {
        var runs: [Run] = []
        var images: [ImageData] = []
        var breakBefore = p.path("w:pPr", "w:pageBreakBefore").map { ($0["w:val"] ?? "1") != "0" } ?? false
        var breakAfter = false
        var fieldLink: String? = nil
        var inInstr = false

        func handleRun(_ r: XNode, link: String?) {
            let style = runStyle(r.child("w:rPr"), link: link ?? fieldLink)
            for c in r.elements {
                switch c.name {
                case "w:t": runs.append(Run(c.textContent, style))
                case "w:tab", "w:ptab": runs.append(Run("\t", style))
                case "w:br", "w:cr":
                    if c["w:type"] == "page" || c["type"] == "page" {
                        if runs.isBlank { breakBefore = true } else { breakAfter = true }
                    } else { runs.append(Run("\n", style)) }
                case "w:noBreakHyphen": runs.append(Run("-", style))
                case "w:sym":
                    if let code = c["w:char"] ?? c["char"], let v = UInt32(code, radix: 16) {
                        // Symbol 字体私有区字符映射到常见符号
                        let mapped: [UInt32: String] = [0xF0B7: "•", 0xF0A7: "▪", 0xF0FC: "✓", 0xF0E0: "→"]
                        runs.append(Run(mapped[v] ?? (Unicode.Scalar(v).map { String(Character($0)) } ?? ""), style))
                    }
                case "w:drawing", "w:pict", "w:object", "mc:AlternateContent":
                    images.append(contentsOf: findImages(c))
                case "w:fldChar":
                    let t = c["w:fldCharType"] ?? c["fldCharType"]
                    if t == "begin" { inInstr = true }
                    else if t == "separate" { inInstr = false }
                    else if t == "end" { inInstr = false; fieldLink = nil }
                case "w:instrText":
                    let instr = c.textContent.trimmingCharacters(in: .whitespaces)
                    if inInstr, instr.hasPrefix("HYPERLINK") {
                        let parts = instr.components(separatedBy: "\"")
                        if parts.count >= 2 { fieldLink = parts[1] }
                    }
                case "w:footnoteReference", "w:endnoteReference": break
                default: break
                }
            }
        }

        func walk(_ nodes: [XNode], link: String?) {
            for n in nodes {
                switch n.name {
                case "w:r": handleRun(n, link: link)
                case "w:hyperlink":
                    var href: String? = nil
                    if let rid = n["r:id"], let t = rels.targets[rid] { href = t }
                    else if let anchor = n["w:anchor"] ?? n["anchor"] { href = "#" + anchor }
                    walk(n.elements, link: href?.hasPrefix("#") == true ? nil : href)
                case "w:ins", "w:smartTag", "w:customXml", "w:fldSimple", "w:dir", "w:bdo":
                    walk(n.elements, link: link)
                case "w:sdt": walk(n.child("w:sdtContent")?.elements ?? [], link: link)
                case "mc:AlternateContent":
                    if let c = n.child("mc:Choice") ?? n.child("mc:Fallback") { walk(c.elements, link: link) }
                case "w:del", "w:moveFrom": continue
                case "m:oMath", "m:oMathPara":
                    runs.append(Run(n.textContent, TextStyle(italic: true)))
                default: continue
                }
            }
        }
        walk(p.elements, link: nil)
        // 不同 run 之间的 "\t" 保留为空格更利于转换
        let normalized = runs.map { r -> Run in var r = r; r.text = r.text.replacingOccurrences(of: "\t", with: "    "); return r }
        return (normalized.normalized(), images, breakBefore, breakAfter)
    }

    func boolProp(_ n: XNode?) -> Bool {
        guard let n = n else { return false }
        let v = n["w:val"] ?? n["val"] ?? "true"
        return v != "0" && v != "false" && v != "none"
    }

    func runStyle(_ rPr: XNode?, link: String?) -> TextStyle {
        var st = TextStyle()
        st.link = link
        guard let rPr = rPr else { return st }
        st.bold = boolProp(rPr.child("w:b"))
        st.italic = boolProp(rPr.child("w:i"))
        st.strike = boolProp(rPr.child("w:strike")) || boolProp(rPr.child("w:dstrike"))
        if let u = rPr.child("w:u") { let v = u["w:val"] ?? u["val"] ?? "single"; st.underline = v != "none" }
        if let rs = rPr.child("w:rStyle").flatMap({ $0["w:val"] ?? $0["val"] }) {
            let name = (styles[rs]?.name ?? rs).lowercased()
            if name.contains("code") || name.contains("verbatim") { st.code = true }
            if name.contains("strong") { st.bold = true }
            if name.contains("emphasis") { st.italic = true }
            if name == "hyperlink" { st.underline = false }
        }
        if let f = rPr.child("w:rFonts").flatMap({ $0["w:ascii"] ?? $0["ascii"] })?.lowercased(),
           ["consolas", "courier new", "courier", "menlo", "monaco", "source code pro", "sf mono", "jetbrains mono"].contains(f) {
            st.code = true
        }
        if link != nil { st.underline = false }
        return st
    }

    func findImages(_ node: XNode) -> [ImageData] {
        var out: [ImageData] = []
        var seen = Set<String>()
        let alt = node.first("wp:docPr").flatMap { $0["descr"] ?? $0["title"] } ?? ""
        for blip in node.descendants("a:blip") {
            if let rid = blip["r:embed"] ?? blip["r:link"], !seen.contains(rid), let path = rels.targets[rid], let d = zip.read(path) {
                seen.insert(rid)
                out.append(ImageData(data: d, mime: ImageInfo.mime(forExtension: (path as NSString).pathExtension), alt: alt))
            }
        }
        if out.isEmpty {
            for im in node.descendants("v:imagedata") {
                if let rid = im["r:id"], !seen.contains(rid), let path = rels.targets[rid], let d = zip.read(path) {
                    seen.insert(rid)
                    out.append(ImageData(data: d, mime: ImageInfo.mime(forExtension: (path as NSString).pathExtension), alt: alt))
                }
            }
        }
        return out
    }

    func parseTable(_ tbl: XNode) -> Table? {
        var rows: [[TableCell]] = []
        var headerRows = 0
        var countingHeader = true
        for tr in expand(tbl.elements) where tr.name == "w:tr" {
            var cells: [TableCell] = []
            for tc in expand(tr.elements) where tc.name == "w:tc" {
                var parts: [Inlines] = []
                for el in expand(tc.elements) {
                    if el.name == "w:p" {
                        let (runs, _, _, _) = paragraphContent(el)
                        parts.append(runs.trimmed())
                    } else if el.name == "w:tbl", let inner = parseTable(el) {
                        parts.append(inner.rows.map { $0.map(\.text).joined(separator: " | ") }.map { Run($0) })
                    }
                }
                while let l = parts.last, l.isEmpty { parts.removeLast() }
                var content: Inlines = []
                for (i, p) in parts.enumerated() {
                    if i > 0 { content.append(Run("\n")) }
                    content.append(contentsOf: p)
                }
                let vMerge = tc.path("w:tcPr", "w:vMerge")
                if let vm = vMerge, (vm["w:val"] ?? vm["val"]) != "restart" { content = [] }
                cells.append(TableCell(content.normalized()))
                let span = Int(tc.path("w:tcPr", "w:gridSpan").flatMap { $0["w:val"] ?? $0["val"] } ?? "1") ?? 1
                if span > 1 { cells.append(contentsOf: Array(repeating: TableCell([]), count: min(span - 1, 63))) }
            }
            if tr.path("w:trPr", "w:tblHeader") != nil && countingHeader { headerRows += 1 } else { countingHeader = false }
            if !cells.isEmpty { rows.append(cells) }
        }
        guard !rows.isEmpty else { return nil }
        return Table(rows: rows, headerRows: max(headerRows, rows.count > 1 ? 1 : 0)).padded()
    }
}

// MARK: 写出

final class DOCXWriter {
    let options: ConversionOptions
    private var rels: [(id: String, type: String, target: String, external: Bool)] = []
    private var media: [(name: String, data: Data)] = []
    private var orderedNums: [Int] = []   // 每个有序列表实例的起始编号，numId = 2 + index
    private var drawingId = 1

    static let nsW = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    init(options: ConversionOptions) { self.options = options }

    var contentWidthEMU: Int { Int((options.pageWidth - options.marginPt * 2) * 12700) }
    var contentHeightEMU: Int { Int((options.pageHeight - options.marginPt * 2) * 12700 * 0.9) }
    var contentWidthTwips: Int { Int((options.pageWidth - options.marginPt * 2) * 20) }

    func addRel(type: String, target: String, external: Bool = false) -> String {
        let id = "rId\(rels.count + 10)"
        rels.append((id, type, target, external))
        return id
    }

    func build(_ doc: Document) -> Data {
        var body = doc.blocks.map { block($0, listLevel: 0, inQuote: false) }.joined()
        if body.isEmpty || !body.hasSuffix("</w:p>") { body += "<w:p/>" }
        let pw = Int(options.pageWidth * 20), ph = Int(options.pageHeight * 20), m = Int(options.marginPt * 20)
        let orient = options.landscape ? " w:orient=\"landscape\"" : ""
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(Self.nsW)" xmlns:r="\(Self.nsR)" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)<w:sectPr><w:pgSz w:w="\(pw)" w:h="\(ph)"\(orient)/><w:pgMar w:top="\(m)" w:right="\(m)" w:bottom="\(m)" w:left="\(m)" w:header="567" w:footer="567" w:gutter="0"/><w:cols w:space="425"/></w:sectPr></w:body></w:document>
        """

        let zip = ZipWriter()
        var ctDefaults = """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>
        """
        for ext in Set(media.map { ($0.name as NSString).pathExtension }) {
            let mime = ImageInfo.mime(forExtension: ext) ?? "image/png"
            ctDefaults += "<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/>"
        }
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\(ctDefaults)<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(Self.relBase)/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="\(Self.relBase)/extended-properties" Target="docProps/app.xml"/></Relationships>
        """)
        zip.add("docProps/core.xml", OOXMLCommon.coreXML(title: doc.effectiveTitle, author: doc.author))
        zip.add("docProps/app.xml", OOXMLCommon.appXML())
        zip.add("word/document.xml", document)
        zip.add("word/styles.xml", stylesXML())
        zip.add("word/numbering.xml", numberingXML())
        zip.add("word/settings.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="\(Self.nsW)"><w:defaultTabStop w:val="420"/><w:characterSpacingControl w:val="compressPunctuation"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
        """)
        var relXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(Self.relBase)/styles" Target="styles.xml"/><Relationship Id="rId2" Type="\(Self.relBase)/numbering" Target="numbering.xml"/><Relationship Id="rId3" Type="\(Self.relBase)/settings" Target="settings.xml"/>
        """
        for r in rels {
            relXML += "<Relationship Id=\"\(r.id)\" Type=\"\(r.type)\" Target=\"\(XML.escape(r.target))\"\(r.external ? " TargetMode=\"External\"" : "")/>"
        }
        relXML += "</Relationships>"
        zip.add("word/_rels/document.xml.rels", relXML)
        for m in media { zip.add("word/media/\(m.name)", m.data, compress: false) }
        return zip.finish()
    }

    // 块

    func pPr(style: String? = nil, extra: String = "") -> String {
        let s = style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? ""
        if s.isEmpty && extra.isEmpty { return "" }
        return "<w:pPr>\(s)\(extra)</w:pPr>"
    }

    func block(_ b: Block, listLevel: Int, inQuote: Bool) -> String {
        switch b {
        case .heading(let level, let c):
            return "<w:p>\(pPr(style: "Heading\(max(1, min(6, level)))"))\(runs(c))</w:p>"
        case .paragraph(let c):
            return "<w:p>\(pPr(style: inQuote ? "Quote" : nil))\(runs(c))</w:p>"
        case .list(let ordered, let start, let items):
            return list(ordered: ordered, start: start, items: items, level: listLevel, numId: nil)
        case .table(let t):
            return table(t) + "<w:p/>"
        case .code(let text, _):
            return text.components(separatedBy: "\n").map { line in
                "<w:p>\(pPr(style: "Code"))<w:r><w:t xml:space=\"preserve\">\(XML.escape(line))</w:t></w:r></w:p>"
            }.joined()
        case .quote(let inner):
            return inner.map { block($0, listLevel: listLevel, inQuote: true) }.joined()
        case .image(let img):
            return "<w:p>\(pPr(extra: "<w:jc w:val=\"center\"/>"))\(imageRun(img))</w:p>"
        case .horizontalRule:
            return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"BFBFBF\"/></w:pBdr></w:pPr></w:p>"
        case .pageBreak:
            return "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
        }
    }

    func list(ordered: Bool, start: Int, items: [ListItem], level: Int, numId: Int?) -> String {
        let lvl = min(level, 8)
        let nid: Int
        if ordered {
            if let n = numId { nid = n } else { orderedNums.append(start); nid = 1 + orderedNums.count }
        } else { nid = 1 }
        var out = ""
        for item in items {
            var first = true
            for b in item.blocks {
                switch b {
                case .paragraph(let c) where first:
                    var prefix = ""
                    if let ch = item.checked { prefix = ch ? "☑ " : "☐ " }
                    out += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(lvl)\"/><w:numId w:val=\"\(nid)\"/></w:numPr></w:pPr>\(prefix.isEmpty ? "" : runs([Run(prefix)]))\(runs(c))</w:p>"
                    first = false
                case .list(let o, let s, let sub):
                    if first {
                        out += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(lvl)\"/><w:numId w:val=\"\(nid)\"/></w:numPr></w:pPr></w:p>"
                        first = false
                    }
                    // 嵌套有序列表复用同一个 numId（多级编号）
                    out += list(ordered: o, start: s, items: sub, level: level + 1, numId: o && ordered ? nid : nil)
                case .paragraph(let c):
                    out += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:ind w:left=\"\(420 * (lvl + 1))\"/></w:pPr>\(runs(c))</w:p>"
                default:
                    if first {
                        out += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(lvl)\"/><w:numId w:val=\"\(nid)\"/></w:numPr></w:pPr></w:p>"
                        first = false
                    }
                    out += block(b, listLevel: level + 1, inQuote: false)
                }
            }
            if first {
                out += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(lvl)\"/><w:numId w:val=\"\(nid)\"/></w:numPr></w:pPr></w:p>"
            }
        }
        return out
    }

    func table(_ t: Table) -> String {
        let t = t.padded()
        let cols = max(1, t.columnCount)
        // 按内容长度分配列宽
        var weights = Array(repeating: 1.0, count: cols)
        for r in t.rows.prefix(50) {
            for (i, c) in r.enumerated() { weights[i] = max(weights[i], min(40, Double(TextUtil.displayWidth(c.text)))) }
        }
        let total = weights.reduce(0, +)
        let widths = weights.map { max(400, Int(Double(contentWidthTwips) * $0 / total)) }
        var x = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/><w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/><w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\"/></w:tblBorders><w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid>"
        x += widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        x += "</w:tblGrid>"
        for (ri, row) in t.rows.enumerated() {
            let header = ri < t.headerRows
            x += "<w:tr>" + (header ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
            for (ci, cell) in row.enumerated() {
                let shd = header ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F2\"/>" : ""
                var content = cell.content
                if header { content = content.map { var r = $0; r.style.bold = true; return r } }
                // 单元格中的换行拆成多个段落
                let paras = splitLines(content)
                x += "<w:tc><w:tcPr><w:tcW w:w=\"\(widths[ci])\" w:type=\"dxa\"/>\(shd)</w:tcPr>"
                x += paras.map { "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/></w:pPr>\(runs($0))</w:p>" }.joined()
                x += "</w:tc>"
            }
            x += "</w:tr>"
        }
        return x + "</w:tbl>"
    }

    func splitLines(_ runs: Inlines) -> [Inlines] {
        var out: [Inlines] = [[]]
        for r in runs {
            let parts = r.text.components(separatedBy: "\n")
            for (i, p) in parts.enumerated() {
                if i > 0 { out.append([]) }
                if !p.isEmpty { out[out.count - 1].append(Run(p, r.style)) }
            }
        }
        return out
    }

    // 行内

    func runs(_ inl: Inlines) -> String {
        var out = ""
        var i = 0
        let rs = inl.normalized()
        while i < rs.count {
            if let link = rs[i].style.link {
                var group: [Run] = []
                while i < rs.count, rs[i].style.link == link { group.append(rs[i]); i += 1 }
                let inner = group.map { run($0, hyperlink: true) }.joined()
                if link.hasPrefix("#") {
                    out += "<w:hyperlink w:anchor=\"\(XML.escape(String(link.dropFirst())))\">\(inner)</w:hyperlink>"
                } else {
                    let rid = addRel(type: "\(Self.relBase)/hyperlink", target: link, external: true)
                    out += "<w:hyperlink r:id=\"\(rid)\">\(inner)</w:hyperlink>"
                }
            } else {
                out += run(rs[i], hyperlink: false)
                i += 1
            }
        }
        return out
    }

    func run(_ r: Run, hyperlink: Bool) -> String {
        var pr = ""
        if hyperlink { pr += "<w:rStyle w:val=\"Hyperlink\"/>" }
        else if r.style.code { pr += "<w:rStyle w:val=\"CodeChar\"/>" }
        if r.style.bold { pr += "<w:b/><w:bCs/>" }
        if r.style.italic { pr += "<w:i/><w:iCs/>" }
        if r.style.strike { pr += "<w:strike/>" }
        if r.style.underline && !hyperlink { pr += "<w:u w:val=\"single\"/>" }
        let rPr = pr.isEmpty ? "" : "<w:rPr>\(pr)</w:rPr>"
        var content = ""
        let lines = r.text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 { content += "<w:br/>" }
            let tabs = line.components(separatedBy: "\t")
            for (j, seg) in tabs.enumerated() {
                if j > 0 { content += "<w:tab/>" }
                if !seg.isEmpty { content += "<w:t xml:space=\"preserve\">\(XML.escape(seg))</w:t>" }
            }
        }
        return "<w:r>\(rPr)\(content)</w:r>"
    }

    func imageRun(_ original: ImageData) -> String {
        guard let img = Platform.officeCompatible(original) else {
            return run(Run(L.imagePlaceholder(original.alt)), hyperlink: false)
        }
        let name = "image\(media.count + 1).\(img.fileExtension)"
        media.append((name, img.data))
        let rid = addRel(type: "\(Self.relBase)/image", target: "media/\(name)")
        var cx = img.pixelWidth > 0 ? img.pixelWidth * 9525 : 4 * 914400
        var cy = img.pixelHeight > 0 ? img.pixelHeight * 9525 : 3 * 914400
        if cx > contentWidthEMU { cy = Int(Double(cy) * Double(contentWidthEMU) / Double(cx)); cx = contentWidthEMU }
        if cy > contentHeightEMU { cx = Int(Double(cx) * Double(contentHeightEMU) / Double(cy)); cy = contentHeightEMU }
        let id = drawingId; drawingId += 1
        let alt = XML.escape(img.alt)
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="\(id)" name="Picture \(id)" descr="\(alt)"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // 样式与编号

    func stylesXML() -> String {
        let sz = Int(options.baseFontSize * 2)
        let headingSizes = [Int(Double(sz) * 2.0), Int(Double(sz) * 1.6), Int(Double(sz) * 1.35), Int(Double(sz) * 1.18), Int(Double(sz) * 1.08), sz]
        var headings = ""
        for l in 1...6 {
            headings += """
            <w:style w:type="paragraph" w:styleId="Heading\(l)"><w:name w:val="heading \(l)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="\(l <= 2 ? 360 : 240)" w:after="120"/><w:outlineLvl w:val="\(l - 1)"/></w:pPr><w:rPr><w:b/><w:bCs/><w:color w:val="\(l <= 2 ? "1F3864" : "2F5496")"/><w:sz w:val="\(headingSizes[l - 1])"/><w:szCs w:val="\(headingSizes[l - 1])"/></w:rPr></w:style>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="\(Self.nsW)"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:eastAsia="PingFang SC" w:hAnsi="Calibri" w:cs="Arial"/><w:sz w:val="\(sz)"/><w:szCs w:val="\(sz)"/><w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\(headings)<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="240"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="\(sz * 2 + 8)"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="D0D7DE"/></w:pBdr><w:ind w:left="420" w:right="420"/></w:pPr><w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style><w:style w:type="paragraph" w:customStyle="1" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F6F8FA"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="210"/></w:pPr><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Consolas"/><w:sz w:val="\(max(sz - 3, 14))"/></w:rPr></w:style><w:style w:type="character" w:customStyle="1" w:styleId="CodeChar"><w:name w:val="Code Char"/><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Consolas"/><w:color w:val="C7254E"/><w:shd w:val="clear" w:color="auto" w:fill="F3F4F6"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:uiPriority w:val="34"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style><w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:uiPriority w:val="99"/><w:unhideWhenUsed/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style><w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="39"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/></w:tblBorders><w:tblCellMar><w:top w:w="57" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="57" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style></w:styles>
        """
    }

    func numberingXML() -> String {
        let bullets = ["•", "◦", "▪"]
        let fmts = ["decimal", "lowerLetter", "lowerRoman"]
        var bulletLvls = "", numLvls = ""
        for l in 0..<9 {
            let ind = 420 * (l + 1)
            bulletLvls += "<w:lvl w:ilvl=\"\(l)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(bullets[l % 3])\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(ind)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
            numLvls += "<w:lvl w:ilvl=\"\(l)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(fmts[l % 3])\"/><w:lvlText w:val=\"%\(l + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(ind)\" w:hanging=\"420\"/></w:pPr></w:lvl>"
        }
        var nums = "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>"
        for (i, start) in orderedNums.enumerated() {
            nums += "<w:num w:numId=\"\(i + 2)\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(start)\"/></w:lvlOverride></w:num>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="\(Self.nsW)"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bulletLvls)</w:abstractNum><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(numLvls)</w:abstractNum>\(nums)</w:numbering>
        """
    }
}

// MARK: - OOXML 公共部件

enum OOXMLCommon {
    static func coreXML(title: String?, author: String?) -> String {
        let fmt = ISO8601DateFormatter()
        let now = fmt.string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(XML.escape(title ?? ""))</dc:title><dc:creator>\(XML.escape(author ?? Platform.generator))</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified></cp:coreProperties>
        """
    }

    static func appXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>\(Platform.generator)</Application></Properties>
        """
    }
}
