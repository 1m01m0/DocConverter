import Foundation

// MARK: - EPUB 3（兼容 EPUB 2 的 toc.ncx）

public struct EPUBFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.epub] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let zip = try ZipArchive(url: url)
        guard let container = zip.read("META-INF/container.xml").flatMap({ XML.parse($0) }),
              let opfPath = container.first("ocf:rootfile")?["full-path"] ?? container.descendants("rootfile").first?["full-path"],
              let opf = zip.read(opfPath).flatMap({ XML.parse($0) }) else {
            throw ConversionError.invalidFile(L.epubNoPackage)
        }
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        var manifest: [String: String] = [:]
        for item in opf.descendants("opf:item") { if let id = item["id"], let href = item["href"] { manifest[id] = href } }
        let spine = opf.descendants("opf:itemref").compactMap { $0["idref"].flatMap { manifest[$0] } }
        let title = opf.first("dc:title")?.textContent
        let author = opf.first("dc:creator")?.textContent

        var blocks: [Block] = []
        for href in spine {
            let path = Relationships.resolve(base: opfDir, target: href.removingPercentEncoding ?? href)
            guard let data = zip.read(path) else { continue }
            let chapterDir = (path as NSString).deletingLastPathComponent
            var conv = HTMLConverter(baseDir: nil)
            conv.imageResolver = { src in
                let p = Relationships.resolve(base: chapterDir, target: src.removingPercentEncoding ?? src)
                guard let d = zip.read(p) else { return nil }
                return ImageData(data: d, mime: ImageInfo.mime(forExtension: (p as NSString).pathExtension))
            }
            let chapter = conv.convert(html: TextDecoder.decode(data))
            if chapter.blocks.isEmpty { continue }
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            blocks.append(contentsOf: chapter.blocks)
        }
        return Document(title: title, author: author, blocks: blocks)
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let title = doc.effectiveTitle ?? url.deletingPathExtension().lastPathComponent
        // 按分页或一级标题拆分章节
        var chapters: [[Block]] = [[]]
        let splitLevel = doc.blocks.contains { if case .heading(1, _) = $0 { return true }; return false } ? 1 : 2
        for b in doc.blocks {
            switch b {
            case .pageBreak:
                if !(chapters.last?.isEmpty ?? true) { chapters.append([]) }
            case .heading(let l, _) where l <= splitLevel:
                if !(chapters.last?.isEmpty ?? true) { chapters.append([]) }
                chapters[chapters.count - 1].append(b)
            default:
                chapters[chapters.count - 1].append(b)
            }
        }
        chapters = chapters.filter { !$0.isEmpty }
        if chapters.isEmpty { chapters = [[.paragraph([Run(title)])]] }

        var images: [(name: String, img: ImageData)] = []
        var writer = HTMLWriter()
        writer.imageSource = { img in
            let name = "image\(images.count + 1).\(img.fileExtension)"
            images.append((name, img))
            return "images/\(name)"
        }

        let zip = ZipWriter()
        zip.add("mimetype", "application/epub+zip", compress: false)
        zip.add("META-INF/container.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """)
        var navItems: [(file: String, label: String)] = []
        for (i, ch) in chapters.enumerated() {
            let file = "chapter\(i + 1).xhtml"
            var label = L.partN(i + 1)
            if case .heading(_, let c)? = ch.first { label = c.plainText }
            navItems.append((file, label))
            let body = ch.map { writer.block($0) }.joined(separator: "\n")
            zip.add("OEBPS/\(file)", """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
            <head><meta charset="utf-8"/><title>\(XML.escape(label))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
            <body>
            \(body)
            </body>
            </html>
            """)
        }
        zip.add("OEBPS/style.css", HTMLWriter.css.replacingOccurrences(of: "max-width: 860px; margin: 2em auto;", with: "margin: 0;"))
        let navList = navItems.map { "<li><a href=\"\($0.file)\">\(XML.escape($0.label))</a></li>" }.joined(separator: "\n")
        zip.add("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
        <head><meta charset="utf-8"/><title>目录</title></head>
        <body><nav epub:type="toc" id="toc"><h1>目录</h1><ol>
        \(navList)
        </ol></nav></body>
        </html>
        """)
        let uid = "urn:uuid:\(UUID().uuidString.lowercased())"
        let ncxPoints = navItems.enumerated().map { i, n in
            "<navPoint id=\"np\(i + 1)\" playOrder=\"\(i + 1)\"><navLabel><text>\(XML.escape(n.label))</text></navLabel><content src=\"\(n.file)\"/></navPoint>"
        }.joined()
        zip.add("OEBPS/toc.ncx", """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="\(uid)"/></head><docTitle><text>\(XML.escape(title))</text></docTitle><navMap>\(ncxPoints)</navMap></ncx>
        """)
        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/><item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>"
        var spine = ""
        for (i, n) in navItems.enumerated() {
            manifest += "<item id=\"c\(i + 1)\" href=\"\(n.file)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(i + 1)\"/>"
        }
        for (i, im) in images.enumerated() {
            zip.add("OEBPS/images/\(im.name)", im.img.data, compress: false)
            manifest += "<item id=\"img\(i + 1)\" href=\"images/\(im.name)\" media-type=\"\(im.img.mime)\"/>"
        }
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        zip.add("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-CN"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">\(uid)</dc:identifier><dc:title>\(XML.escape(title))</dc:title><dc:creator>\(XML.escape(doc.author ?? Platform.generator))</dc:creator><dc:language>zh-CN</dc:language><meta property="dcterms:modified">\(modified)</meta></metadata><manifest>\(manifest)</manifest><spine toc="ncx">\(spine)</spine></package>
        """)
        try zip.finish().write(to: url)
        return [url]
    }
}

// MARK: - LaTeX（仅写出，使用 ctex 支持中文，xelatex 编译）

public struct LaTeXFormat: DocumentWriter {
    public var formats: [Format] { [.tex] }
    public init() {}

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let assetsName = url.deletingPathExtension().lastPathComponent + "_assets"
        var assets: [(String, Data)] = []
        func esc(_ s: String) -> String {
            var o = ""
            for c in s {
                switch c {
                case "\\": o += "\\textbackslash{}"
                case "{", "}", "$", "&", "#", "_", "%": o += "\\\(c)"
                case "^": o += "\\textasciicircum{}"
                case "~": o += "\\textasciitilde{}"
                case "\n": o += "\\\\\n"
                default: o.append(c)
                }
            }
            return o
        }
        func inline(_ runs: Inlines) -> String {
            runs.normalized().map { r in
                var t = r.style.code ? "\\texttt{\(esc(r.text))}" : esc(r.text)
                if r.style.bold { t = "\\textbf{\(t)}" }
                if r.style.italic { t = "\\textit{\(t)}" }
                if r.style.underline { t = "\\underline{\(t)}" }
                if r.style.strike { t = "\\sout{\(t)}" }
                if let l = r.style.link { t = "\\href{\(l.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "#", with: "\\#"))}{\(t)}" }
                return t
            }.joined()
        }
        func block(_ b: Block) -> String {
            switch b {
            case .heading(let l, let c):
                let cmd = ["section", "subsection", "subsubsection", "paragraph", "subparagraph", "subparagraph"][max(1, min(6, l)) - 1]
                return "\\\(cmd){\(inline(c).replacingOccurrences(of: "\\\\\n", with: " "))}"
            case .paragraph(let c): return inline(c)
            case .list(let ordered, let start, let items):
                let env = ordered ? "enumerate" : "itemize"
                var s = "\\begin{\(env)}\n"
                if ordered && start != 1 { s += "\\setcounter{enumi}{\(start - 1)}\n" }
                for it in items {
                    let mark = it.checked.map { $0 ? "[$\\boxtimes$]" : "[$\\square$]" } ?? ""
                    s += "\\item\(mark) " + it.blocks.map(block).joined(separator: "\n\n") + "\n"
                }
                return s + "\\end{\(env)}"
            case .table(let t):
                let t = t.padded()
                let cols = max(1, t.columnCount)
                let w = String(format: "%.3f", 0.95 / Double(cols))
                var s = "\\begin{longtable}{|" + Array(repeating: "p{\(w)\\linewidth}|", count: cols).joined() + "}\n\\hline\n"
                for (i, r) in t.rows.enumerated() {
                    let cells = r.map { c -> String in
                        let x = inline(c.content).replacingOccurrences(of: "\\\\\n", with: " \\newline ")
                        return i < t.headerRows ? "\\textbf{\(x)}" : x
                    }
                    s += cells.joined(separator: " & ") + " \\\\ \\hline\n"
                    if i == t.headerRows - 1 { s += "\\endhead\n" }
                }
                return s + "\\end{longtable}"
            case .code(let text, _): return "\\begin{verbatim}\n\(text)\n\\end{verbatim}"
            case .quote(let inner): return "\\begin{quote}\n" + inner.map(block).joined(separator: "\n\n") + "\n\\end{quote}"
            case .image(let img):
                let name = "image-\(assets.count + 1).\(img.fileExtension)"
                assets.append((name, img.data))
                return "\\begin{center}\n\\includegraphics[width=0.8\\linewidth,keepaspectratio]{\(assetsName)/\(name)}\n\\end{center}"
            case .horizontalRule: return "\\noindent\\rule{\\linewidth}{0.4pt}"
            case .pageBreak: return "\\newpage"
            }
        }
        let body = doc.blocks.map(block).joined(separator: "\n\n")
        let paper = options.pageSize == .letter ? "letterpaper" : "\(options.pageSize.rawValue)paper"
        let tex = """
        % 由 \(Platform.generator) 生成。请使用 xelatex 编译：xelatex "\(url.lastPathComponent)"
        \\documentclass[UTF8,\(paper)]{ctexart}
        \\usepackage[margin=\(Int(options.marginPt))pt]{geometry}
        \\usepackage{graphicx}
        \\usepackage{longtable}
        \\usepackage{amssymb}
        \\usepackage[normalem]{ulem}
        \\usepackage[hidelinks]{hyperref}
        \\title{\(esc(doc.effectiveTitle ?? ""))}
        \\date{}
        \\begin{document}
        \(doc.effectiveTitle == nil ? "" : "\\maketitle\n")
        \(body)

        \\end{document}

        """
        try Data(tex.utf8).write(to: url)
        var out = [url]
        if !assets.isEmpty {
            let dir = url.deletingLastPathComponent().appendingPathComponent(assetsName, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (n, d) in assets { try d.write(to: dir.appendingPathComponent(n)) }
            out.append(dir)
        }
        return out
    }
}
