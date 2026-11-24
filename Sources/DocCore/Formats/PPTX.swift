import Foundation

// MARK: - PowerPoint (.pptx)
// 读取：每页 → 标题 + 正文/表格/图片 + 分页；写出：按 分页 / H1 / H2 拆分为幻灯片，过长内容自动分页

public struct PPTXFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.pptx] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        try PPTXReader(zip: try ZipArchive(url: url), options: options).read()
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        try PPTXWriter(options: options).build(doc).write(to: url)
        return [url]
    }
}

// MARK: 读取

final class PPTXReader {
    let zip: ZipArchive
    let options: ConversionOptions
    init(zip: ZipArchive, options: ConversionOptions) { self.zip = zip; self.options = options }

    struct Shape { var y: Int; var x: Int; var order: Int; var isTitle: Bool; var blocks: [Block]; var titleText: Inlines? }

    func read() throws -> Document {
        let pkg = Relationships(zip: zip, partPath: "")
        let presPath = pkg.first(typeSuffix: "/officeDocument") ?? "ppt/presentation.xml"
        guard let pres = zip.read(presPath).flatMap({ XML.parse($0) }), pres.name == "p:presentation" else {
            throw ConversionError.invalidFile(L.missingPart("presentation.xml"))
        }
        let rels = Relationships(zip: zip, partPath: presPath)
        let slidePaths = (pres.first("p:sldIdLst")?.children("p:sldId") ?? []).compactMap { $0["r:id"].flatMap { rels.targets[$0] } }

        var blocks: [Block] = []
        for (idx, path) in slidePaths.enumerated() {
            guard let xml = zip.read(path).flatMap({ XML.parse($0) }) else { continue }
            if xml["show"] == "0" { continue }
            let srels = Relationships(zip: zip, partPath: path)
            var shapes: [Shape] = []
            var order = 0
            if let tree = xml.first("p:spTree") { collect(tree, rels: srels, into: &shapes, order: &order) }
            shapes.sort { a, b in
                if a.isTitle != b.isTitle { return a.isTitle }
                if abs(a.y - b.y) > 200000 { return a.y < b.y }
                if a.x != b.x { return a.x < b.x }
                return a.order < b.order
            }
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            let titleShape = shapes.first(where: { $0.isTitle && $0.titleText?.isBlank == false })
            let isTitleSlide = idx == 0 && (xml.descendants("p:ph").contains { $0["type"] == "ctrTitle" })
            let title = titleShape?.titleText ?? [Run(L.slideN(idx + 1))]
            blocks.append(.heading(level: isTitleSlide ? 1 : 2, content: title))
            for s in shapes where !(s.isTitle && s.titleText != nil && s.order == titleShape?.order) {
                if s.isTitle, let t = s.titleText, !t.isBlank { blocks.append(.paragraph(t.map { var r = $0; r.style.bold = true; return r })) }
                blocks.append(contentsOf: s.blocks)
            }
            if options.includeSpeakerNotes, let notesPath = srels.first(typeSuffix: "/notesSlide"),
               let notes = zip.read(notesPath).flatMap({ XML.parse($0) }) {
                var text: [Block] = []
                for sp in notes.descendants("p:sp") where sp.first("p:ph")?["type"] == "body" {
                    for p in sp.first("p:txBody")?.children("a:p") ?? [] {
                        let r = paragraphRuns(p, rels: Relationships())
                        if !r.isBlank { text.append(.paragraph(r)) }
                    }
                }
                if !text.isEmpty { blocks.append(.quote([.paragraph([Run(L.speakerNotes, TextStyle(bold: true))])] + text)) }
            }
        }
        return Document(blocks: blocks)
    }

    func offset(_ node: XNode) -> (Int, Int)? {
        guard let off = node.first("a:off") else { return nil }
        return (Int(off["x"] ?? "0") ?? 0, Int(off["y"] ?? "0") ?? 0)
    }

    func collect(_ tree: XNode, rels: Relationships, into shapes: inout [Shape], order: inout Int) {
        for el in tree.elements {
            order += 1
            switch el.name {
            case "p:sp":
                let ph = el.first("p:nvPr")?.child("p:ph")
                let type = ph?["type"]
                let isTitle = type == "title" || type == "ctrTitle"
                if ["dt", "ftr", "sldNum", "hdr"].contains(type ?? "") { continue }
                let pos = offset(el.child("p:spPr") ?? el) ?? (isTitle ? (0, 0) : (Int.max / 4, order))
                guard let body = el.child("p:txBody") else { continue }
                let isBody = ph != nil && !isTitle && type != "subTitle"
                if isTitle {
                    let runs = body.children("a:p").map { paragraphRuns($0, rels: rels) }.filter { !$0.isBlank }
                    var joined: Inlines = []
                    for (i, r) in runs.enumerated() { if i > 0 { joined.append(Run(" ")) }; joined += r }
                    shapes.append(Shape(y: pos.1, x: pos.0, order: order, isTitle: true, blocks: [], titleText: joined.normalized()))
                } else {
                    let bs = textBlocks(body, defaultBullets: isBody, rels: rels)
                    if !bs.isEmpty { shapes.append(Shape(y: pos.1, x: pos.0, order: order, isTitle: false, blocks: bs, titleText: nil)) }
                }
            case "p:graphicFrame":
                let pos = offset(el.child("p:xfrm") ?? el) ?? (Int.max / 4, order)
                if let tbl = el.first("a:tbl") {
                    var rows: [[TableCell]] = []
                    for tr in tbl.children("a:tr") {
                        var cells: [TableCell] = []
                        for tc in tr.children("a:tc") {
                            if tc["hMerge"] == "1" || tc["vMerge"] == "1" { cells.append(TableCell([])); continue }
                            let paras = (tc.child("a:txBody")?.children("a:p") ?? []).map { paragraphRuns($0, rels: rels) }
                            var content: Inlines = []
                            for (i, p) in paras.enumerated() where !p.isBlank || i == 0 {
                                if !content.isEmpty { content.append(Run("\n")) }
                                content += p
                            }
                            cells.append(TableCell(content.trimmed()))
                        }
                        rows.append(cells)
                    }
                    if !rows.isEmpty {
                        let first = tbl.child("a:tblPr")?["firstRow"] == "1"
                        shapes.append(Shape(y: pos.1, x: pos.0, order: order, isTitle: false,
                                            blocks: [.table(Table(rows: rows, headerRows: first || rows.count > 1 ? 1 : 0).padded())], titleText: nil))
                    }
                } else if el.first("c:chart") != nil || el.descendants("a:graphicData").first?["uri"]?.contains("chart") == true {
                    shapes.append(Shape(y: pos.1, x: pos.0, order: order, isTitle: false, blocks: [.paragraph([Run(L.chartPlaceholder, TextStyle(italic: true))])], titleText: nil))
                }
            case "p:pic":
                let pos = offset(el.child("p:spPr") ?? el) ?? (Int.max / 4, order)
                let alt = el.first("p:cNvPr")?["descr"] ?? ""
                if let rid = el.first("a:blip")?["r:embed"], let path = rels.targets[rid], let d = zip.read(path) {
                    let img = ImageData(data: d, mime: ImageInfo.mime(forExtension: (path as NSString).pathExtension), alt: alt)
                    shapes.append(Shape(y: pos.1, x: pos.0, order: order, isTitle: false, blocks: [.image(img)], titleText: nil))
                }
            case "p:grpSp":
                collect(el, rels: rels, into: &shapes, order: &order)
            case "mc:AlternateContent":
                if let c = el.child("mc:Choice") ?? el.child("mc:Fallback") { collect(c, rels: rels, into: &shapes, order: &order) }
            default: break
            }
        }
    }

    func paragraphRuns(_ p: XNode, rels: Relationships) -> Inlines {
        var runs: [Run] = []
        for el in p.elements {
            switch el.name {
            case "a:r", "a:fld":
                var st = TextStyle()
                if let pr = el.child("a:rPr") {
                    st.bold = pr["b"] == "1" || pr["b"] == "true"
                    st.italic = pr["i"] == "1" || pr["i"] == "true"
                    st.underline = (pr["u"] ?? "none") != "none"
                    st.strike = (pr["strike"] ?? "noStrike") != "noStrike"
                    if let rid = pr.child("a:hlinkClick")?["r:id"], let t = rels.targets[rid], rels.external.contains(rid) { st.link = t; st.underline = false }
                    if let f = pr.child("a:latin")?["typeface"]?.lowercased(), ["consolas", "courier new", "menlo", "monaco"].contains(f) { st.code = true }
                }
                runs.append(Run(el.child("a:t")?.textContent ?? "", st))
            case "a:br": runs.append(Run("\n"))
            default: break
            }
        }
        return runs.normalized()
    }

    /// 文本框 → 段落 / 列表（按 lvl 嵌套）
    func textBlocks(_ body: XNode, defaultBullets: Bool, rels: Relationships) -> [Block] {
        struct Item { var level: Int; var ordered: Bool; var bullet: Bool; var runs: Inlines; var start: Int }
        var items: [Item] = []
        for p in body.children("a:p") {
            let runs = paragraphRuns(p, rels: rels)
            if runs.isBlank { continue }
            let pPr = p.child("a:pPr")
            let lvl = Int(pPr?["lvl"] ?? "0") ?? 0
            var bullet = defaultBullets
            var ordered = false
            var start = 1
            if pPr?.child("a:buNone") != nil { bullet = false }
            if pPr?.child("a:buChar") != nil { bullet = true }
            if let an = pPr?.child("a:buAutoNum") { bullet = true; ordered = true; start = Int(an["startAt"] ?? "1") ?? 1 }
            items.append(Item(level: lvl, ordered: ordered, bullet: bullet, runs: runs.trimmed(), start: start))
        }
        var blocks: [Block] = []
        var i = 0
        func buildList(_ slice: ArraySlice<Item>) -> Block {
            let base = slice.first!.level
            var listItems: [ListItem] = []
            var j = slice.startIndex
            while j < slice.endIndex {
                if slice[j].level <= base {
                    listItems.append(ListItem([.paragraph(slice[j].runs)])); j += 1
                } else {
                    var k = j
                    while k < slice.endIndex, slice[k].level > base { k += 1 }
                    let nested = buildList(slice[j..<k])
                    if listItems.isEmpty { listItems.append(ListItem([])) }
                    listItems[listItems.count - 1].blocks.append(nested)
                    j = k
                }
            }
            return .list(ordered: slice.first!.ordered, start: slice.first!.start, items: listItems)
        }
        while i < items.count {
            if items[i].bullet {
                var j = i
                while j < items.count, items[j].bullet { j += 1 }
                blocks.append(buildList(items[i..<j]))
                i = j
            } else {
                blocks.append(.paragraph(items[i].runs))
                i += 1
            }
        }
        return blocks
    }
}

// MARK: 写出

final class PPTXWriter {
    let options: ConversionOptions
    init(options: ConversionOptions) { self.options = options }

    static let slideW = 12192000, slideH = 6858000
    static let marginX = 838200
    static let contentTop = 1690688
    static var contentW: Int { slideW - marginX * 2 }
    static var contentH: Int { slideH - contentTop - 457200 }

    struct TextItem { var runs: Inlines; var level: Int; var bullet: Bullet; var mono = false; var italic = false; var bold = false }
    enum Bullet: Equatable { case none, char, number(start: Int) }

    final class Slide {
        var title: Inlines
        var subtitle: Inlines? = nil
        var isTitleSlide = false
        var texts: [TextItem] = []
        var table: Table? = nil
        var image: ImageData? = nil
        init(title: Inlines) { self.title = title }
        var isEmpty: Bool { texts.isEmpty && table == nil && image == nil }
        var weight: Int { texts.reduce(0) { $0 + max(1, TextUtil.displayWidth($1.runs.plainText) / 90 + 1) } }
    }

    // 拆分文档为幻灯片

    func makeSlides(_ doc: Document) -> [Slide] {
        var slides: [Slide] = []
        let docTitle = doc.effectiveTitle ?? L.untitledPresentation
        var current: Slide? = nil
        let split = max(1, min(6, options.slideSplitLevel))

        func cur() -> Slide {
            if let c = current { return c }
            let s = Slide(title: [Run(slides.isEmpty ? docTitle : (slides.last.map { $0.title.plainText } ?? docTitle))])
            slides.append(s); current = s
            return s
        }
        func continuation() -> Slide {
            let base = current?.title.plainText ?? docTitle
            let t = base.hasSuffix(L.continuedSuffix) ? base : base + L.continuedSuffix
            let s = Slide(title: [Run(t)])
            slides.append(s); current = s
            return s
        }
        func addText(_ items: [TextItem]) {
            for it in items {
                var s = cur()
                if s.table != nil || s.image != nil || s.isTitleSlide || s.weight >= 9 || s.texts.count >= 12 { s = continuation() }
                s.texts.append(it)
            }
        }
        func listItems(_ ordered: Bool, _ start: Int, _ items: [ListItem], level: Int) -> [TextItem] {
            var out: [TextItem] = []
            for (i, item) in items.enumerated() {
                var first = true
                for b in item.blocks {
                    switch b {
                    case .paragraph(let c):
                        var runs = c
                        if let ch = item.checked, first { runs.insert(Run(ch ? "☑ " : "☐ "), at: 0) }
                        out.append(TextItem(runs: runs, level: min(level, 4), bullet: first ? (ordered ? .number(start: start) : .char) : .none))
                        first = false
                    case .list(let o, let s, let sub):
                        out.append(contentsOf: listItems(o, s, sub, level: level + 1))
                    default:
                        let lines = TextUtil.plainLines([b])
                        out.append(contentsOf: lines.map { TextItem(runs: [Run($0)], level: min(level + 1, 4), bullet: .none) })
                    }
                }
                _ = i
            }
            return out
        }

        for (bi, b) in doc.blocks.enumerated() {
            switch b {
            case .pageBreak:
                current = nil
            case .heading(let level, let c) where level <= split:
                // 只有一级标题 + 简短副标题的开头部分做成封面
                let s = Slide(title: c)
                if slides.isEmpty && level == 1 && split >= 2 {
                    let rest = doc.blocks.dropFirst(bi + 1)
                    let next = rest.first
                    let following = rest.dropFirst().first
                    func isSplit(_ x: Block?) -> Bool {
                        if case .heading(let l, _)? = x { return l <= split }
                        if case .pageBreak? = x { return true }
                        return x == nil
                    }
                    if isSplit(next) { s.isTitleSlide = true }
                    else if case .paragraph(let p)? = next, TextUtil.displayWidth(p.plainText) < 120, isSplit(following) {
                        s.isTitleSlide = true
                    }
                }
                slides.append(s); current = s
            case .heading(_, let c):
                addText([TextItem(runs: c, level: 0, bullet: .none, bold: true)])
            case .paragraph(let c):
                if let s = current, s.isTitleSlide, s.subtitle == nil { s.subtitle = c; continue }
                addText([TextItem(runs: c, level: 0, bullet: .none)])
            case .list(let ordered, let start, let items):
                addText(listItems(ordered, start, items, level: 0))
            case .code(let text, _):
                addText(text.components(separatedBy: "\n").map { TextItem(runs: [Run($0.isEmpty ? " " : $0)], level: 0, bullet: .none, mono: true) })
            case .quote(let inner):
                addText(TextUtil.plainLines(inner).map { TextItem(runs: [Run($0)], level: 0, bullet: .none, italic: true) })
            case .table(let t):
                let t = t.padded()
                let header = Array(t.rows.prefix(t.headerRows))
                let body = Array(t.rows.dropFirst(t.headerRows))
                let perSlide = max(4, 12 - header.count)
                var chunks: [[[TableCell]]] = stride(from: 0, to: max(body.count, 1), by: perSlide).map { Array(body[$0..<min($0 + perSlide, body.count)]) }
                if body.isEmpty { chunks = [[]] }
                for chunk in chunks {
                    var s = cur()
                    if !s.isEmpty || s.isTitleSlide { s = continuation() }
                    if let n = t.name, s.title.plainText.isEmpty || (slides.count == 1 && s.title.plainText == docTitle) { s.title = [Run(n)] }
                    s.table = Table(rows: header + chunk, headerRows: header.count, name: t.name)
                }
            case .image(let img):
                var s = cur()
                if !s.isEmpty || s.isTitleSlide { s = continuation() }
                s.image = img
            case .horizontalRule:
                break
            }
        }
        // 去掉完全空的普通幻灯片（保留封面）
        slides = slides.filter { !$0.isEmpty || $0.isTitleSlide || !$0.title.isBlank }
        if slides.isEmpty { slides = [Slide(title: [Run(docTitle)])]; slides[0].isTitleSlide = true }
        return slides
    }

    // 打包

    func build(_ doc: Document) -> Data {
        let slides = makeSlides(doc)
        let zip = ZipWriter()
        var mediaExts = Set<String>()
        var mediaCount = 0

        var slideOverrides = ""
        var presRels = "<Relationship Id=\"rId1\" Type=\"\(Rel.slideMaster)\" Target=\"slideMasters/slideMaster1.xml\"/>"
        var sldIds = ""
        for (i, s) in slides.enumerated() {
            var rels: [String] = []
            let layout = s.isTitleSlide ? 1 : ((s.table != nil || s.image != nil) ? 3 : 2)
            rels.append("<Relationship Id=\"rId1\" Type=\"\(Rel.slideLayout)\" Target=\"../slideLayouts/slideLayout\(layout).xml\"/>")
            func addRel(_ type: String, _ target: String, external: Bool = false) -> String {
                let id = "rId\(rels.count + 1)"
                rels.append("<Relationship Id=\"\(id)\" Type=\"\(type)\" Target=\"\(XML.escape(target))\"\(external ? " TargetMode=\"External\"" : "")/>")
                return id
            }
            var imageRel: String? = nil
            var image: ImageData? = nil
            if let original = s.image, let img = Platform.officeCompatible(original) {
                mediaCount += 1
                let name = "image\(mediaCount).\(img.fileExtension)"
                zip.add("ppt/media/\(name)", img.data, compress: false)
                mediaExts.insert(img.fileExtension)
                imageRel = addRel(Rel.image, "../media/\(name)")
                image = img
            }
            let xml = slideXML(s, image: image, imageRel: imageRel, linkRel: { addRel(Rel.hyperlink, $0, external: true) })
            zip.add("ppt/slides/slide\(i + 1).xml", xml)
            zip.add("ppt/slides/_rels/slide\(i + 1).xml.rels", relsXML(rels.joined()))
            slideOverrides += "<Override PartName=\"/ppt/slides/slide\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
            presRels += "<Relationship Id=\"rId\(i + 2)\" Type=\"\(Rel.slide)\" Target=\"slides/slide\(i + 1).xml\"/>"
            sldIds += "<p:sldId id=\"\(256 + i)\" r:id=\"rId\(i + 2)\"/>"
        }
        let n = slides.count
        presRels += "<Relationship Id=\"rId\(n + 2)\" Type=\"\(Rel.theme)\" Target=\"theme/theme1.xml\"/>"
        presRels += "<Relationship Id=\"rId\(n + 3)\" Type=\"\(Rel.presProps)\" Target=\"presProps.xml\"/>"
        presRels += "<Relationship Id=\"rId\(n + 4)\" Type=\"\(Rel.viewProps)\" Target=\"viewProps.xml\"/>"
        presRels += "<Relationship Id=\"rId\(n + 5)\" Type=\"\(Rel.tableStyles)\" Target=\"tableStyles.xml\"/>"

        var defaults = "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        for e in mediaExts.sorted() { defaults += "<Default Extension=\"\(e)\" ContentType=\"\(ImageInfo.mime(forExtension: e) ?? "image/png")\"/>" }
        let pml = "application/vnd.openxmlformats-officedocument.presentationml"
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\(defaults)<Override PartName="/ppt/presentation.xml" ContentType="\(pml).presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="\(pml).slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="\(pml).slideLayout+xml"/><Override PartName="/ppt/slideLayouts/slideLayout2.xml" ContentType="\(pml).slideLayout+xml"/><Override PartName="/ppt/slideLayouts/slideLayout3.xml" ContentType="\(pml).slideLayout+xml"/>\(slideOverrides)<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/ppt/presProps.xml" ContentType="\(pml).presProps+xml"/><Override PartName="/ppt/viewProps.xml" ContentType="\(pml).viewProps+xml"/><Override PartName="/ppt/tableStyles.xml" ContentType="\(pml).tableStyles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """)
        zip.add("_rels/.rels", relsXML("<Relationship Id=\"rId1\" Type=\"\(Rel.officeDocument)\" Target=\"ppt/presentation.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"\(Rel.base)/extended-properties\" Target=\"docProps/app.xml\"/>"))
        zip.add("docProps/core.xml", OOXMLCommon.coreXML(title: doc.effectiveTitle, author: doc.author))
        zip.add("docProps/app.xml", OOXMLCommon.appXML())
        zip.add("ppt/presentation.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation \(PPTXWriter.ns) saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(sldIds)</p:sldIdLst><p:sldSz cx="\(PPTXWriter.slideW)" cy="\(PPTXWriter.slideH)"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="zh-CN"/></a:defPPr></p:defaultTextStyle></p:presentation>
        """)
        zip.add("ppt/_rels/presentation.xml.rels", relsXML(presRels))
        zip.add("ppt/presProps.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<p:presentationPr \(PPTXWriter.ns)/>")
        zip.add("ppt/viewProps.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<p:viewPr \(PPTXWriter.ns)><p:normalViewPr><p:restoredLeft sz=\"15620\"/><p:restoredTop sz=\"94660\"/></p:normalViewPr><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>")
        zip.add("ppt/tableStyles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>")
        zip.add("ppt/theme/theme1.xml", PPTXTemplates.theme)
        zip.add("ppt/slideMasters/slideMaster1.xml", PPTXTemplates.master)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", relsXML("<Relationship Id=\"rId1\" Type=\"\(Rel.slideLayout)\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"\(Rel.slideLayout)\" Target=\"../slideLayouts/slideLayout2.xml\"/><Relationship Id=\"rId3\" Type=\"\(Rel.slideLayout)\" Target=\"../slideLayouts/slideLayout3.xml\"/><Relationship Id=\"rId4\" Type=\"\(Rel.theme)\" Target=\"../theme/theme1.xml\"/>"))
        for (i, l) in [PPTXTemplates.layoutTitle, PPTXTemplates.layoutContent, PPTXTemplates.layoutTitleOnly].enumerated() {
            zip.add("ppt/slideLayouts/slideLayout\(i + 1).xml", l)
            zip.add("ppt/slideLayouts/_rels/slideLayout\(i + 1).xml.rels", relsXML("<Relationship Id=\"rId1\" Type=\"\(Rel.slideMaster)\" Target=\"../slideMasters/slideMaster1.xml\"/>"))
        }
        return zip.finish()
    }

    enum Rel {
        static let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        static let officeDocument = base + "/officeDocument"
        static let slide = base + "/slide"
        static let slideLayout = base + "/slideLayout"
        static let slideMaster = base + "/slideMaster"
        static let theme = base + "/theme"
        static let image = base + "/image"
        static let hyperlink = base + "/hyperlink"
        static let presProps = base + "/presProps"
        static let viewProps = base + "/viewProps"
        static let tableStyles = base + "/tableStyles"
    }

    static let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""

    func relsXML(_ inner: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(inner)</Relationships>"
    }

    // 幻灯片 XML

    func runsXML(_ runs: Inlines, size: Int? = nil, mono: Bool = false, italic: Bool = false, bold: Bool = false, linkRel: (String) -> String) -> String {
        var out = ""
        for r in runs.normalized() {
            let parts = r.text.components(separatedBy: "\n")
            for (i, part) in parts.enumerated() {
                var attrs = "lang=\"zh-CN\" altLang=\"en-US\""
                if let s = size { attrs += " sz=\"\(s)\"" }
                if r.style.bold || bold { attrs += " b=\"1\"" }
                if r.style.italic || italic { attrs += " i=\"1\"" }
                if r.style.underline { attrs += " u=\"sng\"" }
                if r.style.strike { attrs += " strike=\"sngStrike\"" }
                attrs += " dirty=\"0\""
                var children = ""
                if r.style.code || mono { children += "<a:latin typeface=\"Menlo\"/><a:cs typeface=\"Consolas\"/>" }
                if let l = r.style.link, !l.hasPrefix("#") { children += "<a:hlinkClick r:id=\"\(linkRel(l))\"/>" }
                if i > 0 { out += "<a:br><a:rPr \(attrs)/></a:br>" }
                if !part.isEmpty {
                    out += "<a:r><a:rPr \(attrs)\(children.isEmpty ? "/>" : ">\(children)</a:rPr>")<a:t>\(XML.escape(part))</a:t></a:r>"
                }
            }
        }
        return out
    }

    func sp(id: Int, name: String, ph: String, x: Int, y: Int, cx: Int, cy: Int, body: String, bodyPr: String = "<a:bodyPr><a:normAutofit/></a:bodyPr>") -> String {
        """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="\(name)"/>\(ph.isEmpty ? "<p:cNvSpPr txBox=\"1\"/>" : "<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>")<p:nvPr>\(ph)</p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm></p:spPr><p:txBody>\(bodyPr)<a:lstStyle/>\(body)</p:txBody></p:sp>
        """
    }

    func slideXML(_ s: Slide, image: ImageData?, imageRel: String?, linkRel: (String) -> String) -> String {
        var shapes = ""
        let mx = PPTXWriter.marginX, cw = PPTXWriter.contentW
        if s.isTitleSlide {
            shapes += sp(id: 2, name: "Title 1", ph: "<p:ph type=\"ctrTitle\"/>", x: 1524000, y: 1122363, cx: 9144000, cy: 2387600,
                         body: "<a:p><a:pPr algn=\"ctr\"/>\(runsXML(s.title, size: 4400, linkRel: linkRel))</a:p>", bodyPr: "<a:bodyPr anchor=\"b\"><a:normAutofit/></a:bodyPr>")
            if let sub = s.subtitle {
                shapes += sp(id: 3, name: "Subtitle 2", ph: "<p:ph type=\"subTitle\" idx=\"1\"/>", x: 1524000, y: 3602038, cx: 9144000, cy: 1655762,
                             body: "<a:p><a:pPr marL=\"0\" indent=\"0\" algn=\"ctr\"><a:buNone/></a:pPr>\(runsXML(sub, size: 2400, linkRel: linkRel))</a:p>")
            }
        } else {
            shapes += sp(id: 2, name: "Title 1", ph: "<p:ph type=\"title\"/>", x: mx, y: 365125, cx: cw, cy: 1100000,
                         body: "<a:p>\(runsXML(s.title, linkRel: linkRel))</a:p>")
            if !s.texts.isEmpty {
                let base = s.texts.count > 8 || s.weight > 7 ? 2000 : 2400
                let paras = s.texts.map { t -> String in
                    var pPr: String
                    let marL = 342900 + t.level * 457200
                    switch t.bullet {
                    case .none:
                        pPr = "<a:pPr marL=\"\(t.level * 457200)\" lvl=\"\(t.level)\" indent=\"0\"><a:buNone/></a:pPr>"
                    case .char:
                        pPr = "<a:pPr marL=\"\(marL)\" lvl=\"\(t.level)\" indent=\"-342900\"><a:buFont typeface=\"Arial\"/><a:buChar char=\"\(t.level % 2 == 0 ? "•" : "–")\"/></a:pPr>"
                    case .number(let start):
                        pPr = "<a:pPr marL=\"\(marL)\" lvl=\"\(t.level)\" indent=\"-342900\"><a:buFont typeface=\"+mj-lt\"/><a:buAutoNum type=\"arabicPeriod\"\(start != 1 ? " startAt=\"\(start)\"" : "")/></a:pPr>"
                    }
                    let size = t.mono ? base - 600 : base - t.level * 200
                    return "<a:p>\(pPr)\(runsXML(t.runs, size: size, mono: t.mono, italic: t.italic, bold: t.bold, linkRel: linkRel))</a:p>"
                }.joined()
                shapes += sp(id: 3, name: "Content Placeholder 2", ph: "<p:ph idx=\"1\"/>", x: mx, y: PPTXWriter.contentTop, cx: cw, cy: PPTXWriter.contentH, body: paras)
            }
            if let t = s.table { shapes += tableXML(t, linkRel: linkRel) }
            if let img = image, let rid = imageRel {
                var w = img.pixelWidth > 0 ? img.pixelWidth * 9525 : cw
                var h = img.pixelHeight > 0 ? img.pixelHeight * 9525 : PPTXWriter.contentH
                let scale = min(Double(cw) / Double(w), Double(PPTXWriter.contentH) / Double(h), 1.0)
                w = Int(Double(w) * scale); h = Int(Double(h) * scale)
                let x = (PPTXWriter.slideW - w) / 2
                let y = PPTXWriter.contentTop + (PPTXWriter.contentH - h) / 2
                shapes += """
                <p:pic><p:nvPicPr><p:cNvPr id="5" name="Picture 4" descr="\(XML.escape(img.alt))"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>
                """
            } else if let original = s.image {
                shapes += sp(id: 5, name: "Text 4", ph: "", x: mx, y: PPTXWriter.contentTop, cx: cw, cy: 800000,
                             body: "<a:p>\(runsXML([Run(L.imagePlaceholder(original.alt))], linkRel: linkRel))</a:p>")
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld \(PPTXWriter.ns)><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
        """
    }

    func tableXML(_ t: Table, linkRel: (String) -> String) -> String {
        let t = t.padded()
        let cols = max(1, t.columnCount)
        var weights = Array(repeating: 1.0, count: cols)
        for r in t.rows { for (i, c) in r.enumerated() { weights[i] = max(weights[i], min(30, Double(TextUtil.displayWidth(c.text)))) } }
        let total = weights.reduce(0, +)
        let cw = PPTXWriter.contentW
        var widths = weights.map { Int(Double(cw) * $0 / total) }
        widths[widths.count - 1] += cw - widths.reduce(0, +)
        let fontSize = cols > 6 || t.rows.count > 10 ? 1200 : 1400
        let rowH = fontSize == 1200 ? 330000 : 370840
        let border = "<a:solidFill><a:srgbClr val=\"BFBFBF\"/></a:solidFill>"
        func ln(_ tag: String) -> String { "<a:\(tag) w=\"9525\">\(border)</a:\(tag)>" }
        var rows = ""
        for (ri, r) in t.rows.enumerated() {
            let header = ri < t.headerRows
            rows += "<a:tr h=\"\(rowH)\">"
            for c in r {
                let fill = header ? "<a:solidFill><a:srgbClr val=\"2F5496\"/></a:solidFill>" : (ri % 2 == 0 ? "<a:solidFill><a:srgbClr val=\"F2F2F2\"/></a:solidFill>" : "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>")
                var runs = runsXML(c.content, size: fontSize, bold: header, linkRel: linkRel)
                if header { runs = runs.replacingOccurrences(of: "dirty=\"0\"/>", with: "dirty=\"0\"><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill></a:rPr>")
                                    .replacingOccurrences(of: "dirty=\"0\"><a:latin", with: "dirty=\"0\"><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:latin") }
                rows += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>\(runs)<a:endParaRPr lang=\"zh-CN\" sz=\"\(fontSize)\" dirty=\"0\"/></a:p></a:txBody><a:tcPr marL=\"91440\" marR=\"91440\" marT=\"45720\" marB=\"45720\">\(ln("lnL"))\(ln("lnR"))\(ln("lnT"))\(ln("lnB"))\(fill)</a:tcPr></a:tc>"
            }
            rows += "</a:tr>"
        }
        let height = rowH * t.rows.count
        return """
        <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="4" name="Table 3"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="\(PPTXWriter.marginX)" y="\(PPTXWriter.contentTop)"/><a:ext cx="\(cw)" cy="\(height)"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="\(t.headerRows > 0 ? 1 : 0)" bandRow="1"/><a:tblGrid>\(widths.map { "<a:gridCol w=\"\($0)\"/>" }.joined())</a:tblGrid>\(rows)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>
        """
    }
}

// MARK: 模板部件（主题 / 母版 / 版式）

enum PPTXTemplates {
    static let ns = PPTXWriter.ns

    static let theme = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F3864"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="2F5496"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Hans" typeface="等线 Light"/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Hans" typeface="等线"/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:tint val="50000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:shade val="80000"/></a:schemeClr></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln><a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:tint val="95000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:shade val="90000"/></a:schemeClr></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
    """

    static let clrMap = "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"

    static let groupHeader = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    static func placeholder(id: Int, name: String, ph: String, x: Int, y: Int, cx: Int, cy: Int, anchor: String = "t", text: String = "", lstStyle: String = "<a:lstStyle/>") -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr>\(ph)</p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\" anchor=\"\(anchor)\"><a:normAutofit/></a:bodyPr>\(lstStyle)<a:p><a:r><a:rPr lang=\"zh-CN\" altLang=\"en-US\"/><a:t>\(text)</a:t></a:r></a:p></p:txBody></p:sp>"
    }

    static func level(_ n: Int, size: Int, bullet: Bool) -> String {
        let marL = 228600 + (n - 1) * 457200
        let bu = bullet ? "<a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>" : "<a:buNone/>"
        return "<a:lvl\(n)pPr marL=\"\(marL)\" indent=\"-228600\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\"><a:lnSpc><a:spcPct val=\"100000\"/></a:lnSpc><a:spcBef><a:spcPts val=\"600\"/></a:spcBef>\(bu)<a:defRPr sz=\"\(size)\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl\(n)pPr>"
    }

    static var master: String {
        let body = (1...5).map { level($0, size: [2800, 2400, 2000, 1800, 1800][$0 - 1], bullet: true) }.joined()
        let other = "<a:defPPr><a:defRPr lang=\"zh-CN\"/></a:defPPr>" + (1...5).map { level($0, size: 1800, bullet: false) }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster \(ns)><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\(groupHeader)\(placeholder(id: 2, name: "Title Placeholder 1", ph: "<p:ph type=\"title\"/>", x: 838200, y: 365125, cx: 10515600, cy: 1100000, anchor: "ctr", text: L.placeholderTitle))\(placeholder(id: 3, name: "Text Placeholder 2", ph: "<p:ph type=\"body\" idx=\"1\"/>", x: 838200, y: 1690688, cx: 10515600, cy: 4710112, text: L.placeholderBody))</p:spTree></p:cSld>\(clrMap)<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/><p:sldLayoutId id="2147483650" r:id="rId2"/><p:sldLayoutId id="2147483651" r:id="rId3"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef><a:buNone/><a:defRPr sz="3600" b="1" kern="1200"><a:solidFill><a:schemeClr val="tx2"/></a:solidFill><a:latin typeface="+mj-lt"/><a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr></p:titleStyle><p:bodyStyle>\(body)</p:bodyStyle><p:otherStyle>\(other)</p:otherStyle></p:txStyles></p:sldMaster>
        """
    }

    static func layout(type: String, name: String, shapes: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout \(ns) type="\(type)" preserve="1"><p:cSld name="\(name)"><p:spTree>\(groupHeader)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """
    }

    static var layoutTitle: String { layout(type: "title", name: "Title Slide", shapes:
        placeholder(id: 2, name: "Title 1", ph: "<p:ph type=\"ctrTitle\"/>", x: 1524000, y: 1122363, cx: 9144000, cy: 2387600, anchor: "b", text: L.placeholderTitle)
        + placeholder(id: 3, name: "Subtitle 2", ph: "<p:ph type=\"subTitle\" idx=\"1\"/>", x: 1524000, y: 3602038, cx: 9144000, cy: 1655762, text: L.placeholderSubtitle,
                      lstStyle: "<a:lstStyle><a:lvl1pPr marL=\"0\" indent=\"0\" algn=\"ctr\"><a:buNone/><a:defRPr sz=\"2400\"/></a:lvl1pPr></a:lstStyle>")) }

    static var layoutContent: String { layout(type: "obj", name: "Title and Content", shapes:
        placeholder(id: 2, name: "Title 1", ph: "<p:ph type=\"title\"/>", x: 838200, y: 365125, cx: 10515600, cy: 1100000, anchor: "ctr", text: L.placeholderTitle)
        + placeholder(id: 3, name: "Content Placeholder 2", ph: "<p:ph idx=\"1\"/>", x: 838200, y: 1690688, cx: 10515600, cy: 4710112, text: L.placeholderBody)) }

    static var layoutTitleOnly: String { layout(type: "titleOnly", name: "Title Only", shapes:
        placeholder(id: 2, name: "Title 1", ph: "<p:ph type=\"title\"/>", x: 838200, y: 365125, cx: 10515600, cy: 1100000, anchor: "ctr", text: L.placeholderTitle)) }
}
