import Foundation

// MARK: - HTML（宽松解析器 + 转换 + 写出）

public struct HTMLFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.html] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let text = try TextDecoder.read(url)
        return HTMLConverter(baseDir: url.deletingLastPathComponent()).convert(html: text)
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let html = HTMLWriter().render(doc, standalone: true)
        try Data(html.utf8).write(to: url)
        return [url]
    }
}

// MARK: 实体

public enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
        "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "bull": "•", "middot": "·", "times": "×", "divide": "÷", "deg": "°", "plusmn": "±", "para": "¶", "sect": "§",
        "laquo": "«", "raquo": "»", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "rarr": "→", "larr": "←",
        "uarr": "↑", "darr": "↓", "harr": "↔", "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "infin": "∞",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwj": "\u{200D}", "zwnj": "\u{200C}",
        "shy": "\u{00AD}", "iexcl": "¡", "iquest": "¿", "frac12": "½", "frac14": "¼", "frac34": "¾", "check": "✓",
    ]

    /// 解码单个实体（包含 & 和 ;）
    public static func decode(_ ent: String) -> String? {
        guard ent.hasPrefix("&"), ent.hasSuffix(";"), ent.count >= 3 else { return nil }
        let body = String(ent.dropFirst().dropLast())
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            if let v = UInt32(body.dropFirst(2), radix: 16), let s = Unicode.Scalar(v) { return String(Character(s)) }
            return nil
        }
        if body.hasPrefix("#") {
            if let v = UInt32(body.dropFirst()), let s = Unicode.Scalar(v) { return String(Character(s)) }
            return nil
        }
        return named[body]
    }

    public static func decodeAll(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";"), let d = decode(String(s[i...semi])) {
                out += d
                i = s.index(after: semi)
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }
}

// MARK: DOM

public final class HNode {
    public let tag: String           // 小写标签名；文本节点为 "#text"
    public var attrs: [String: String]
    public var children: [HNode] = []
    public var text = ""
    weak var parent: HNode?

    init(tag: String, attrs: [String: String] = [:]) { self.tag = tag; self.attrs = attrs }
    var isText: Bool { tag == "#text" }

    public var textContent: String { isText ? text : children.map(\.textContent).joined() }

    func find(_ t: String) -> HNode? {
        for c in children {
            if c.tag == t { return c }
            if let f = c.find(t) { return f }
        }
        return nil
    }
}

public enum HTMLParser {
    static let voidTags: Set<String> = ["br", "hr", "img", "meta", "link", "input", "col", "area", "base", "embed",
                                        "source", "wbr", "param", "track"]
    static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]
    static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "table", "pre",
                                         "blockquote", "section", "article", "header", "footer", "nav", "aside", "main",
                                         "figure", "hr", "dl", "form", "address", "fieldset"]

    public static func parse(_ html: String) -> HNode {
        let root = HNode(tag: "#root")
        var stack: [HNode] = [root]
        let s = Array(html)
        var i = 0
        var text = ""

        func flushText() {
            guard !text.isEmpty else { return }
            let t = HNode(tag: "#text")
            t.text = HTMLEntities.decodeAll(text)
            t.parent = stack.last
            stack.last!.children.append(t)
            text = ""
        }
        func popTo(_ tag: String, stopAt: Set<String> = []) -> Bool {
            guard let idx = stack.lastIndex(where: { $0.tag == tag }) else { return false }
            if stack[(idx + 1)...].contains(where: { stopAt.contains($0.tag) }) { return false }
            stack.removeSubrange(idx...)
            return true
        }
        func hasPrefix(_ p: String, at j: Int) -> Bool {
            let pc = Array(p)
            guard j + pc.count <= s.count else { return false }
            for k in 0..<pc.count where Character(s[j + k].lowercased()) != pc[k] { return false }
            return true
        }

        while i < s.count {
            let c = s[i]
            guard c == "<" else { text.append(c); i += 1; continue }
            // 注释
            if hasPrefix("<!--", at: i) {
                flushText()
                var j = i + 4
                while j < s.count && !hasPrefix("-->", at: j) { j += 1 }
                let comment = String(s[min(i + 4, s.count)..<min(j, s.count)]).trimmingCharacters(in: .whitespaces).lowercased()
                if comment == "pagebreak" {
                    let n = HNode(tag: "pagebreak"); n.parent = stack.last; stack.last!.children.append(n)
                }
                i = j + 3; continue
            }
            if hasPrefix("<![cdata[", at: i) {
                var j = i + 9
                while j < s.count && !hasPrefix("]]>", at: j) { j += 1 }
                text += String(s[(i + 9)..<min(j, s.count)])
                i = j + 3; continue
            }
            if hasPrefix("<!", at: i) || hasPrefix("<?", at: i) {
                flushText()
                while i < s.count && s[i] != ">" { i += 1 }
                i += 1; continue
            }
            // 结束标签
            if i + 1 < s.count && s[i + 1] == "/" {
                var j = i + 2
                var name = ""
                while j < s.count && s[j] != ">" { name.append(s[j]); j += 1 }
                name = name.trimmingCharacters(in: .whitespaces).lowercased()
                if let sp = name.firstIndex(of: " ") { name = String(name[..<sp]) }
                if let colon = name.lastIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
                flushText()
                _ = popTo(name)
                i = j + 1; continue
            }
            // 开始标签
            guard i + 1 < s.count, s[i + 1].isLetter else { text.append(c); i += 1; continue }
            var j = i + 1
            var name = ""
            while j < s.count && !s[j].isWhitespace && s[j] != ">" && s[j] != "/" { name.append(s[j]); j += 1 }
            name = name.lowercased()
            if let colon = name.lastIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
            var attrs: [String: String] = [:]
            var selfClosing = false
            // 属性
            while j < s.count && s[j] != ">" {
                if s[j] == "/" { selfClosing = true; j += 1; continue }
                if s[j].isWhitespace { j += 1; continue }
                var an = ""
                while j < s.count && !s[j].isWhitespace && s[j] != "=" && s[j] != ">" && s[j] != "/" { an.append(s[j]); j += 1 }
                while j < s.count && s[j].isWhitespace { j += 1 }
                var av = ""
                if j < s.count && s[j] == "=" {
                    j += 1
                    while j < s.count && s[j].isWhitespace { j += 1 }
                    if j < s.count && (s[j] == "\"" || s[j] == "'") {
                        let q = s[j]; j += 1
                        while j < s.count && s[j] != q { av.append(s[j]); j += 1 }
                        j += 1
                    } else {
                        while j < s.count && !s[j].isWhitespace && s[j] != ">" { av.append(s[j]); j += 1 }
                    }
                }
                if !an.isEmpty { attrs[an.lowercased()] = HTMLEntities.decodeAll(av) }
                selfClosing = false
            }
            i = j + 1
            flushText()

            // 隐式闭合
            if blockTags.contains(name) || name == "li" || name == "dt" || name == "dd" { _ = popTo("p", stopAt: ["table", "li", "blockquote", "div"]) }
            if name == "li" { _ = popTo("li", stopAt: ["ul", "ol"]) }
            if name == "dt" || name == "dd" { _ = popTo("dt", stopAt: ["dl"]); _ = popTo("dd", stopAt: ["dl"]) }
            if name == "td" || name == "th" { _ = popTo("td", stopAt: ["tr", "table"]); _ = popTo("th", stopAt: ["tr", "table"]) }
            if name == "tr" { _ = popTo("tr", stopAt: ["table"]) }
            if name == "option" { _ = popTo("option", stopAt: ["select"]) }

            let node = HNode(tag: name, attrs: attrs)
            node.parent = stack.last
            stack.last!.children.append(node)

            if rawTextTags.contains(name) && !selfClosing {
                let close = "</\(name)"
                var k = i
                while k < s.count && !hasPrefix(close, at: k) { k += 1 }
                let raw = String(s[min(i, s.count)..<min(k, s.count)])
                let t = HNode(tag: "#text"); t.text = name == "textarea" || name == "title" ? HTMLEntities.decodeAll(raw) : raw
                node.children.append(t)
                while k < s.count && s[k] != ">" { k += 1 }
                i = k + 1
                continue
            }
            if !voidTags.contains(name) && !selfClosing { stack.append(node) }
        }
        flushText()
        return root
    }
}

// MARK: HTML → Document

public struct HTMLConverter {
    let baseDir: URL?
    /// 自定义图片解析（EPUB 等从压缩包中读取图片）
    public var imageResolver: ((String) -> ImageData?)? = nil
    public init(baseDir: URL?) { self.baseDir = baseDir }

    public func convert(html: String) -> Document {
        let root = HTMLParser.parse(html)
        let title = root.find("title")?.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = root.find("body") ?? root
        var blocks = convertChildren(body.children, style: .plain)
        // 去掉与 <title> 重复的空段
        blocks = blocks.filter { if case .paragraph(let r) = $0 { return !r.isBlank } else { return true } }
        return Document(title: title?.isEmpty == false ? title : nil, blocks: blocks)
    }

    static let skipTags: Set<String> = ["script", "style", "head", "title", "meta", "link", "noscript", "template",
                                        "svg", "button", "input", "select", "nav", "iframe", "object"]

    func isBlock(_ n: HNode) -> Bool {
        HTMLParser.blockTags.contains(n.tag) || ["li", "tr", "td", "th", "dt", "dd", "img", "pagebreak", "figcaption",
                                                  "tbody", "thead", "caption", "center"].contains(n.tag)
            || (n.tag == "div")
    }

    func convertChildren(_ nodes: [HNode], style: TextStyle) -> [Block] {
        var blocks: [Block] = []
        var runs: [Run] = []
        func flush() {
            let r = collapse(runs)
            if !r.isBlank { blocks.append(.paragraph(r)) }
            runs = []
        }
        for n in nodes {
            if n.isText { runs.append(Run(n.text, style)); continue }
            if Self.skipTags.contains(n.tag) { continue }
            if isPageBreak(n) { flush(); blocks.append(.pageBreak); continue }
            switch n.tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                let level = Int(String(n.tag.last!)) ?? 1
                let r = collapse(inlineRuns(n.children, style: style))
                if !r.isBlank { blocks.append(.heading(level: level, content: r)) }
            case "p", "figcaption", "caption", "address", "center", "dt":
                flush()
                blocks.append(contentsOf: splitImages(inlineTokens(n.children, style: style)))
            case "div", "section", "article", "main", "header", "footer", "aside", "figure", "form", "fieldset", "body", "html", "dl", "dd", "tbody", "thead":
                flush()
                blocks.append(contentsOf: convertChildren(n.children, style: style))
            case "br":
                runs.append(Run("\n", style))
            case "hr":
                flush(); blocks.append(.horizontalRule)
            case "img":
                if let img = image(n) { flush(); blocks.append(.image(img)) }
            case "pre":
                flush()
                var lang: String? = nil
                if let code = n.find("code"), let cls = code.attrs["class"] {
                    lang = cls.split(separator: " ").first(where: { $0.hasPrefix("language-") || $0.hasPrefix("lang-") })
                        .map { String($0.split(separator: "-", maxSplits: 1).last ?? "") }
                }
                var t = n.textContent
                if t.hasPrefix("\n") { t.removeFirst() }
                while t.hasSuffix("\n") { t.removeLast() }
                blocks.append(.code(text: t, language: lang))
            case "blockquote":
                flush()
                blocks.append(.quote(convertChildren(n.children, style: style)))
            case "ul", "ol":
                flush()
                blocks.append(list(n, style: style))
            case "li":
                flush()
                blocks.append(.list(ordered: false, start: 1, items: [ListItem(convertChildren(n.children, style: style))]))
            case "table":
                flush()
                if let t = table(n) { blocks.append(.table(t)) }
            default:
                // 行内元素：如果里面含块元素（例如 <a><div>..），递归按块处理
                if containsBlock(n) {
                    flush()
                    blocks.append(contentsOf: convertChildren(n.children, style: applyInline(n, style)))
                } else {
                    for t in inlineTokens([n], style: style) {
                        switch t {
                        case .run(let r): runs.append(r)
                        case .image(let img): flush(); blocks.append(.image(img))
                        }
                    }
                }
            }
        }
        flush()
        return blocks
    }

    func containsBlock(_ n: HNode) -> Bool {
        n.children.contains { !$0.isText && ((isBlock($0) && $0.tag != "img") || containsBlock($0)) }
    }

    func isPageBreak(_ n: HNode) -> Bool {
        if n.tag == "pagebreak" { return true }
        let st = (n.attrs["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        return (st.contains("page-break-after:always") || st.contains("page-break-before:always") || st.contains("break-after:page"))
            && n.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func image(_ n: HNode) -> ImageData? {
        guard let src = n.attrs["src"] ?? n.attrs["xlink:href"] ?? n.attrs["href"] else { return nil }
        if let r = imageResolver, var img = r(src) { img.alt = n.attrs["alt"] ?? ""; return img }
        return TextUtil.loadImage(src: src, baseDir: baseDir, alt: n.attrs["alt"] ?? "")
    }

    func applyInline(_ n: HNode, _ style: TextStyle) -> TextStyle {
        var st = style
        switch n.tag {
        case "b", "strong": st.bold = true
        case "i", "em", "cite", "var", "dfn": st.italic = true
        case "u", "ins": st.underline = true
        case "s", "del", "strike": st.strike = true
        case "code", "kbd", "samp", "tt": st.code = true
        case "a": if let h = n.attrs["href"], !h.hasPrefix("#"), !h.lowercased().hasPrefix("javascript:") { st.link = h }
        default: break
        }
        let css = (n.attrs["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        if css.contains("font-weight:bold") || css.contains("font-weight:700") || css.contains("font-weight:600") { st.bold = true }
        if css.contains("font-style:italic") { st.italic = true }
        if css.contains("text-decoration:underline") { st.underline = true }
        if css.contains("line-through") { st.strike = true }
        return st
    }

    enum Token { case run(Run), image(ImageData) }

    func inlineTokens(_ nodes: [HNode], style: TextStyle) -> [Token] {
        var out: [Token] = []
        for n in nodes {
            if n.isText { out.append(.run(Run(n.text, style))); continue }
            if Self.skipTags.contains(n.tag) { continue }
            switch n.tag {
            case "br": out.append(.run(Run("\n", style)))
            case "img": if let img = image(n) { out.append(.image(img)) }
            default:
                // 行内元素中的块级元素（如 <p> 嵌在 <td> 中）之间加换行
                let isBlk = isBlock(n) && n.tag != "img"
                if isBlk, !out.isEmpty { out.append(.run(Run("\n", style))) }
                out.append(contentsOf: inlineTokens(n.children, style: applyInline(n, style)))
                if isBlk { out.append(.run(Run("\n", style))) }
            }
        }
        return out
    }

    func inlineRuns(_ nodes: [HNode], style: TextStyle) -> [Run] {
        inlineTokens(nodes, style: style).compactMap { if case .run(let r) = $0 { return r }; return nil }
    }

    func splitImages(_ toks: [Token]) -> [Block] {
        var out: [Block] = []
        var runs: [Run] = []
        for t in toks {
            switch t {
            case .run(let r): runs.append(r)
            case .image(let img):
                let c = collapse(runs); if !c.isBlank { out.append(.paragraph(c)) }
                runs = []
                out.append(.image(img))
            }
        }
        let c = collapse(runs); if !c.isBlank { out.append(.paragraph(c)) }
        return out
    }

    /// HTML 空白折叠：连续空白 → 一个空格；中日韩字符间的换行直接删除；保留 <br> 产生的 "\n"
    func collapse(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        var lastChar: Character? = nil
        for r in runs {
            if r.style.code && r.text.contains("\n") == false {
                out.append(r); lastChar = r.text.last; continue
            }
            if r.text == "\n" {
                if let l = out.last, l.text.hasSuffix(" ") { out[out.count - 1].text.removeLast() }
                if lastChar != "\n" && lastChar != nil { out.append(r); lastChar = "\n" }
                continue
            }
            var t = ""
            var pendingSpace = false
            var pendingHadNewline = false
            for ch in r.text {
                if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{000C}" {
                    pendingSpace = true
                    if ch == "\n" { pendingHadNewline = true }
                    continue
                }
                if pendingSpace {
                    let prev = t.last ?? lastChar
                    if let p = prev, p != "\n" {
                        if !(pendingHadNewline && TextUtil.isCJK(p) && TextUtil.isCJK(ch)) { t.append(" ") }
                    }
                    pendingSpace = false; pendingHadNewline = false
                }
                t.append(ch == "\u{00A0}" ? " " : ch)
            }
            if pendingSpace, let p = t.last ?? lastChar, p != "\n", p != " " { t.append(" ") }
            if !t.isEmpty { out.append(Run(t, r.style)); lastChar = t.last }
        }
        return out.trimmed()
    }

    func list(_ n: HNode, style: TextStyle) -> Block {
        var items: [ListItem] = []
        for c in n.children where c.tag == "li" {
            var checked: Bool? = nil
            if let input = c.find("input"), input.attrs["type"]?.lowercased() == "checkbox" {
                checked = input.attrs["checked"] != nil
            }
            items.append(ListItem(convertChildren(c.children, style: style), checked: checked))
        }
        // 非 li 的直接子节点（不规范 HTML）
        if items.isEmpty { items = [ListItem(convertChildren(n.children, style: style))] }
        let start = Int(n.attrs["start"] ?? "1") ?? 1
        return .list(ordered: n.tag == "ol", start: start, items: items)
    }

    func table(_ n: HNode) -> Table? {
        var rows: [[TableCell]] = []
        var headerRows = 0
        var allHeader = true
        func walk(_ x: HNode, inHead: Bool) {
            for c in x.children {
                switch c.tag {
                case "thead": walk(c, inHead: true)
                case "tbody", "tfoot": walk(c, inHead: false)
                case "tr":
                    var cells: [TableCell] = []
                    var rowAllTh = true
                    for cell in c.children where cell.tag == "td" || cell.tag == "th" {
                        if cell.tag != "th" { rowAllTh = false }
                        let runs = collapse(inlineRuns(cell.children, style: cell.tag == "th" ? TextStyle() : TextStyle()))
                        cells.append(TableCell(runs))
                        let span = Int(cell.attrs["colspan"] ?? "1") ?? 1
                        if span > 1 { cells.append(contentsOf: Array(repeating: TableCell([]), count: min(span - 1, 50))) }
                    }
                    if !cells.isEmpty {
                        if (inHead || rowAllTh) && allHeader { headerRows += 1 } else { allHeader = false }
                        rows.append(cells)
                    }
                case "table": break   // 嵌套表格忽略
                default: walk(c, inHead: inHead)
                }
            }
        }
        walk(n, inHead: false)
        guard !rows.isEmpty else { return nil }
        if headerRows == rows.count { headerRows = min(1, rows.count) }
        return Table(rows: rows, headerRows: headerRows).padded()
    }
}

// MARK: Document → HTML（输出为合法 XHTML，同时可被 EPUB 复用）

public struct HTMLWriter {
    /// 图片引用方式，默认 data URI 内嵌
    public var imageSource: (ImageData) -> String = { TextUtil.base64DataURI($0) }
    public init() {}

    public static let css = """
    body { font-family: -apple-system, "PingFang SC", "Helvetica Neue", "Microsoft YaHei", Arial, sans-serif;
           line-height: 1.7; color: #1f2328; max-width: 860px; margin: 2em auto; padding: 0 1.2em; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.4em 0 0.6em; }
    h1 { font-size: 2em; border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }
    p { margin: 0.6em 0; }
    a { color: #0969da; }
    code { font-family: Menlo, Consolas, monospace; background: #f3f4f6; padding: .15em .35em; border-radius: 4px; font-size: .9em; }
    pre { background: #f6f8fa; padding: 1em; border-radius: 6px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 1em 0; padding: 0 1em; color: #57606a; border-left: .25em solid #d0d7de; }
    table { border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid #d0d7de; padding: 6px 12px; vertical-align: top; }
    th { background: #f6f8fa; font-weight: 600; }
    img { max-width: 100%; height: auto; }
    hr { border: none; border-top: 1px solid #d0d7de; margin: 2em 0; }
    .page-break { page-break-after: always; break-after: page; height: 0; }
    @media print { body { max-width: none; margin: 0; } }
    """

    public func render(_ doc: Document, standalone: Bool) -> String {
        let body = doc.blocks.map { block($0) }.joined(separator: "\n")
        guard standalone else { return body }
        let title = XML.escape(doc.effectiveTitle ?? L.untitledDocument)
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(title)</title>
        <style>
        \(HTMLWriter.css)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>

        """
    }

    public func block(_ b: Block) -> String {
        switch b {
        case .heading(let level, let c):
            let l = max(1, min(6, level))
            return "<h\(l)>\(inline(c))</h\(l)>"
        case .paragraph(let c):
            return "<p>\(inline(c))</p>"
        case .list(let ordered, let start, let items):
            let tag = ordered ? "ol" : "ul"
            let startAttr = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let lis = items.map { item -> String in
                var inner = item.blocks.map { block($0) }.joined(separator: "\n")
                // 紧凑列表：单段落不包 <p>
                if item.blocks.count == 1, case .paragraph(let c) = item.blocks[0] { inner = inline(c) }
                if let ch = item.checked {
                    inner = "<input type=\"checkbox\" disabled=\"disabled\"\(ch ? " checked=\"checked\"" : "") /> " + inner
                }
                return "<li>\(inner)</li>"
            }.joined(separator: "\n")
            return "<\(tag)\(startAttr)>\n\(lis)\n</\(tag)>"
        case .table(let t):
            let t = t.padded()
            var rows: [String] = []
            for (i, r) in t.rows.enumerated() {
                let isHead = i < t.headerRows
                let cells = r.map { c in isHead ? "<th>\(inline(c.content))</th>" : "<td>\(inline(c.content))</td>" }.joined()
                rows.append("<tr>\(cells)</tr>")
            }
            let head = rows.prefix(t.headerRows).joined(separator: "\n")
            let body = rows.dropFirst(t.headerRows).joined(separator: "\n")
            return "<table>\n" + (head.isEmpty ? "" : "<thead>\n\(head)\n</thead>\n") + "<tbody>\n\(body)\n</tbody>\n</table>"
        case .code(let text, let lang):
            let cls = lang.map { " class=\"language-\(XML.escape($0))\"" } ?? ""
            return "<pre><code\(cls)>\(XML.escape(text))</code></pre>"
        case .quote(let inner):
            return "<blockquote>\n\(inner.map { block($0) }.joined(separator: "\n"))\n</blockquote>"
        case .image(let img):
            var size = ""
            if img.pixelWidth > 0 { size = " width=\"\(img.pixelWidth)\"" }
            return "<p><img src=\"\(XML.escape(imageSource(img)))\" alt=\"\(XML.escape(img.alt))\"\(size) /></p>"
        case .horizontalRule:
            return "<hr />"
        case .pageBreak:
            return "<div class=\"page-break\" style=\"page-break-after: always;\"></div>"
        }
    }

    public func inline(_ runs: [Run]) -> String {
        var out = ""
        for r in runs.normalized() {
            var t = XML.escape(r.text).replacingOccurrences(of: "\n", with: "<br />")
            if r.style.code { t = "<code>\(t)</code>" }
            if r.style.strike { t = "<del>\(t)</del>" }
            if r.style.underline { t = "<u>\(t)</u>" }
            if r.style.italic { t = "<em>\(t)</em>" }
            if r.style.bold { t = "<strong>\(t)</strong>" }
            if let l = r.style.link { t = "<a href=\"\(XML.escape(l))\">\(t)</a>" }
            out += t
        }
        return out
    }
}
