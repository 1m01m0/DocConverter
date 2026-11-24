import Foundation

// MARK: - Markdown（CommonMark 常用子集 + GFM 表格 / 删除线 / 任务列表）

public struct MarkdownFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.md] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let text = try TextDecoder.read(url)
        return MarkdownParser(baseDir: url.deletingLastPathComponent()).parse(text)
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let assetsName = url.deletingPathExtension().lastPathComponent + "_assets"
        let w = MarkdownWriter(assetsDirName: assetsName, embed: options.embedImagesInMarkdown)
        let text = w.render(doc)
        try Data(text.utf8).write(to: url)
        var outputs = [url]
        if !w.assets.isEmpty {
            let dir = url.deletingLastPathComponent().appendingPathComponent(assetsName, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, data) in w.assets { try data.write(to: dir.appendingPathComponent(name)) }
            outputs.append(dir)
        }
        return outputs
    }
}

// MARK: 解析

public struct MarkdownParser {
    let baseDir: URL?
    public init(baseDir: URL? = nil) { self.baseDir = baseDir }

    public func parse(_ source: String) -> Document {
        var text = TextDecoder.normalizeNewlines(source)
        var title: String? = nil
        // YAML front matter
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let front = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in front.split(separator: "\n") where line.hasPrefix("title:") {
                title = line.dropFirst(6).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            text = String(text[end.upperBound...])
        }
        let lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\t", with: "    ") }
        return Document(title: title, blocks: parseBlocks(lines))
    }

    // 行类型判断

    static func indent(_ s: String) -> Int { s.prefix(while: { $0 == " " }).count }
    static func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }

    static func headingMatch(_ s: String) -> (Int, String)? {
        let t = s.drop(while: { $0 == " " })
        guard indent(s) < 4, t.hasPrefix("#") else { return nil }
        let level = t.prefix(while: { $0 == "#" }).count
        guard level <= 6 else { return nil }
        let rest = t.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var content = rest.trimmingCharacters(in: .whitespaces)
        // 去掉结尾的 ###
        if let r = content.range(of: #"\s+#+$"#, options: .regularExpression) { content.removeSubrange(r) }
        else if content.allSatisfy({ $0 == "#" }) { content = "" }
        return (level, content)
    }

    static func isHR(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.count >= 3, indent(s) < 4, let c = t.first, "-*_".contains(c) else { return false }
        return t.allSatisfy { $0 == c }
    }

    static func fenceMatch(_ s: String) -> (String, String)? {
        let t = s.drop(while: { $0 == " " })
        guard indent(s) < 4 else { return nil }
        for ch in ["`", "~"] {
            let n = t.prefix(while: { String($0) == ch }).count
            if n >= 3 {
                let info = t.dropFirst(n).trimmingCharacters(in: .whitespaces)
                if ch == "`" && info.contains("`") { return nil }
                return (String(repeating: ch, count: n), info)
            }
        }
        return nil
    }

    /// 列表标记：(缩进, 是否有序, 起始编号, 内容起始列, 内容)
    static func listMatch(_ s: String) -> (indent: Int, ordered: Bool, number: Int, contentCol: Int, content: String, marker: Character)? {
        let ind = indent(s)
        let t = Array(s.dropFirst(ind))
        guard !t.isEmpty else { return nil }
        if "-*+".contains(t[0]) {
            if t.count == 1 { return (ind, false, 1, ind + 2, "", t[0]) }
            guard t[1] == " " else { return nil }
            let spaces = t.dropFirst(1).prefix(while: { $0 == " " }).count
            let col = ind + 1 + (spaces > 4 ? 1 : spaces)
            return (ind, false, 1, col, String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces), t[0])
        }
        let digits = t.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9, t.count > digits.count else { return nil }
        let delim = t[digits.count]
        guard delim == "." || delim == ")" else { return nil }
        let after = t.dropFirst(digits.count + 1)
        if !after.isEmpty && after.first != " " { return nil }
        let spaces = after.prefix(while: { $0 == " " }).count
        let col = ind + digits.count + 1 + (spaces > 4 || spaces == 0 ? 1 : spaces)
        return (ind, true, Int(String(digits)) ?? 1, col, String(after).trimmingCharacters(in: .whitespaces), delim)
    }

    static func isTableDelimiter(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        let cells = splitTableRow(t)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { c in
            let x = c.trimmingCharacters(in: .whitespaces)
            return !x.isEmpty && x.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
        }
    }

    static func splitTableRow(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var cur = ""
        var inCode = false
        var prev: Character = " "
        for ch in t {
            if ch == "`" { inCode.toggle() }
            if ch == "|" && prev != "\\" && !inCode { cells.append(cur); cur = "" }
            else if ch == "|" && prev == "\\" { cur.removeLast(); cur.append("|") }
            else { cur.append(ch) }
            prev = ch
        }
        cells.append(cur)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isPageBreak(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        return t == "\\newpage" || t == "\\pagebreak" || t == "<!-- pagebreak -->"
            || (t.hasPrefix("<div") && t.contains("page-break-after") && t.hasSuffix("</div>"))
    }

    func startsBlock(_ s: String) -> Bool {
        Self.headingMatch(s) != nil || Self.fenceMatch(s) != nil || Self.isHR(s)
            || s.trimmingCharacters(in: .whitespaces).hasPrefix(">") || Self.isPageBreak(s)
            || (Self.listMatch(s).map { !$0.content.isEmpty && ($0.ordered ? $0.number == 1 : true) } ?? false)
    }

    func parseBlocks(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if Self.isBlank(line) { i += 1; continue }

            if Self.isPageBreak(line) { blocks.append(.pageBreak); i += 1; continue }

            if let (fence, info) = Self.fenceMatch(line) {
                let ind = Self.indent(line)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    let lt = l.trimmingCharacters(in: .whitespaces)
                    if lt.hasPrefix(fence) && lt.allSatisfy({ String($0) == String(fence.first!) }) { i += 1; break }
                    code.append(String(l.dropFirst(min(ind, Self.indent(l)))))
                    i += 1
                }
                let lang = info.split(separator: " ").first.map(String.init)
                blocks.append(.code(text: code.joined(separator: "\n"), language: lang?.isEmpty == false ? lang : nil))
                continue
            }

            if let (level, content) = Self.headingMatch(line) {
                blocks.append(.heading(level: level, content: inlineRuns(content)))
                i += 1; continue
            }

            if Self.isHR(line) { blocks.append(.horizontalRule); i += 1; continue }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count, !Self.isBlank(lines[i]) {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        l.removeFirst()
                        if l.hasPrefix(" ") { l.removeFirst() }
                    } else if startsBlock(lines[i]) { break }
                    inner.append(l)
                    i += 1
                }
                blocks.append(.quote(parseBlocks(inner)))
                continue
            }

            if line.contains("|"), i + 1 < lines.count, Self.isTableDelimiter(lines[i + 1]) {
                var rows: [[TableCell]] = [Self.splitTableRow(line).map { TableCell(inlineRuns($0)) }]
                i += 2
                while i < lines.count, !Self.isBlank(lines[i]), lines[i].contains("|") {
                    rows.append(Self.splitTableRow(lines[i]).map { TableCell(inlineRuns($0)) })
                    i += 1
                }
                blocks.append(.table(Table(rows: rows, headerRows: 1).padded()))
                continue
            }

            if let first = Self.listMatch(line) {
                let (list, next) = parseList(lines, from: i, first: first)
                blocks.append(list)
                i = next
                continue
            }

            if Self.indent(line) >= 4 {
                var code: [String] = []
                while i < lines.count, Self.indent(lines[i]) >= 4 || Self.isBlank(lines[i]) {
                    code.append(String(lines[i].dropFirst(min(4, Self.indent(lines[i])))))
                    i += 1
                }
                while let l = code.last, Self.isBlank(l) { code.removeLast() }
                blocks.append(.code(text: code.joined(separator: "\n"), language: nil))
                continue
            }

            // 段落（含 setext 标题）
            var para: [String] = [line.trimmingCharacters(in: .whitespaces)]
            i += 1
            var setext = 0
            while i < lines.count, !Self.isBlank(lines[i]) {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && t.allSatisfy({ $0 == "=" }) { setext = 1; i += 1; break }
                if !t.isEmpty && t.allSatisfy({ $0 == "-" }) && para.count >= 1 { setext = 2; i += 1; break }
                if startsBlock(l) { break }
                if l.contains("|"), i + 1 < lines.count, Self.isTableDelimiter(lines[i + 1]) { break }
                // 保留行尾两个空格（硬换行标记），只去掉行首空白
                para.append(String(l.drop(while: { $0 == " " })))
                i += 1
            }
            let joined = para.joined(separator: "\n")
            if setext > 0 {
                blocks.append(.heading(level: setext, content: inlineRuns(joined)))
            } else {
                blocks.append(contentsOf: paragraphBlocks(joined))
            }
        }
        return blocks
    }

    func parseList(_ lines: [String], from start: Int, first: (indent: Int, ordered: Bool, number: Int, contentCol: Int, content: String, marker: Character)) -> (Block, Int) {
        var items: [ListItem] = []
        var i = start
        var cur: [String] = []
        var contentCol = first.contentCol
        var hasItem = false

        func flush() {
            guard hasItem else { return }
            var checked: Bool? = nil
            if var f = cur.first {
                if f.hasPrefix("[ ] ") || f == "[ ]" { checked = false; f = String(f.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                else if f.lowercased().hasPrefix("[x] ") || f.lowercased() == "[x]" { checked = true; f = String(f.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                cur[0] = f
            }
            items.append(ListItem(parseBlocks(cur), checked: checked))
            cur = []
        }

        while i < lines.count {
            let l = lines[i]
            if Self.isBlank(l) {
                // 空行后若仍是缩进内容或同级列表项则继续
                var j = i + 1
                while j < lines.count, Self.isBlank(lines[j]) { j += 1 }
                guard j < lines.count else { break }
                let nl = lines[j]
                if let m = Self.listMatch(nl), m.indent < contentCol, m.ordered == first.ordered, m.indent <= first.indent + 1 {
                    cur.append(""); i = j; continue
                }
                if Self.indent(nl) >= contentCol { cur.append(""); i = j; continue }
                break
            }
            if let m = Self.listMatch(l), m.indent < contentCol {
                // 同级新列表项
                if m.ordered != first.ordered || (m.indent < first.indent) { break }
                if !first.ordered && m.marker != first.marker { break }
                flush()
                hasItem = true
                contentCol = m.contentCol
                cur = [m.content]
                i += 1
                continue
            }
            if Self.indent(l) >= contentCol {
                cur.append(String(l.dropFirst(contentCol)))
                i += 1
                continue
            }
            // 懒惰续行
            if hasItem, !startsBlock(l), let last = cur.last, !Self.isBlank(last) {
                cur.append(l.trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }
            break
        }
        flush()
        return (.list(ordered: first.ordered, start: first.number, items: items), i)
    }

    // MARK: 行内

    enum Token { case run(Run), image(ImageData) }

    /// 段落可能包含图片：拆分为 段落 / 图片 / 段落
    func paragraphBlocks(_ text: String) -> [Block] {
        let toks = inlineTokens(text, style: .plain)
        var out: [Block] = []
        var runs: [Run] = []
        for t in toks {
            switch t {
            case .run(let r): runs.append(r)
            case .image(let img):
                let n = runs.trimmed()
                if !n.isEmpty { out.append(.paragraph(n)) }
                runs = []
                out.append(.image(img))
            }
        }
        let n = runs.trimmed()
        if !n.isEmpty { out.append(.paragraph(n)) }
        return out
    }

    func inlineRuns(_ text: String) -> [Run] {
        inlineTokens(text, style: .plain).compactMap {
            if case .run(let r) = $0 { return r }
            if case .image(let img) = $0 { return Run(img.alt.isEmpty ? "" : "[\(img.alt)]") }
            return nil
        }.normalized()
    }

    func inlineTokens(_ text: String, style: TextStyle) -> [Token] {
        let chars = Array(text)
        var out: [Token] = []
        var buf = ""
        var i = 0

        func flushBuf() {
            if !buf.isEmpty { out.append(.run(Run(buf, style))); buf = "" }
        }
        func findClose(_ delim: [Character], from: Int) -> Int? {
            var j = from
            while j + delim.count <= chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if chars[j] == "`" {
                    let n = chars[j...].prefix(while: { $0 == "`" }).count
                    if let e = findBackticks(n, from: j + n) { j = e + n; continue }
                }
                if Array(chars[j..<(j + delim.count)]) == delim, j > from, chars[j - 1] != " " {
                    // 单个 * 不应匹配 ** 的一部分
                    if delim.count == 1, j + 1 < chars.count, chars[j + 1] == delim[0] { j += 2; continue }
                    return j
                }
                j += 1
            }
            return nil
        }
        func findBackticks(_ n: Int, from: Int) -> Int? {
            var j = from
            while j < chars.count {
                if chars[j] == "`" {
                    let m = chars[j...].prefix(while: { $0 == "`" }).count
                    if m == n { return j }
                    j += m
                } else { j += 1 }
            }
            return nil
        }
        func findBracketEnd(_ from: Int) -> Int? {
            var depth = 0
            var j = from
            while j < chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if chars[j] == "[" { depth += 1 }
                if chars[j] == "]" { depth -= 1; if depth == 0 { return j } }
                j += 1
            }
            return nil
        }
        func parseLinkTarget(_ from: Int) -> (String, Int)? {
            guard from < chars.count, chars[from] == "(" else { return nil }
            var j = from + 1
            var depth = 1
            var s = ""
            while j < chars.count {
                if chars[j] == "(" { depth += 1 }
                if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                s.append(chars[j]); j += 1
            }
            guard j < chars.count else { return nil }
            var url = s.trimmingCharacters(in: .whitespaces)
            if url.hasPrefix("<"), let e = url.firstIndex(of: ">") { url = String(url[url.index(after: url.startIndex)..<e]) }
            else if let sp = url.firstIndex(of: " ") { url = String(url[..<sp]) }   // 去掉 "title"
            return (url, j + 1)
        }

        while i < chars.count {
            let c = chars[i]
            // 转义
            if c == "\\", i + 1 < chars.count {
                let n = chars[i + 1]
                if n == "\n" { buf.append("\n"); i += 2; continue }
                if n.isPunctuation || n.isSymbol { buf.append(n); i += 2; continue }
            }
            // 换行：两个以上空格 = 硬换行，否则软换行
            if c == "\n" {
                if buf.hasSuffix("  ") {
                    while buf.hasSuffix(" ") { buf.removeLast() }
                    buf.append("\n")
                } else {
                    while buf.hasSuffix(" ") { buf.removeLast() }
                    let prev = buf.last ?? out.lastText
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    if let p = prev, (TextUtil.isCJK(p) && TextUtil.isCJK(next)) { } else { buf.append(" ") }
                }
                i += 1; continue
            }
            // 行内代码
            if c == "`" {
                let n = chars[i...].prefix(while: { $0 == "`" }).count
                if let e = findBackticks(n, from: i + n) {
                    flushBuf()
                    var code = String(chars[(i + n)..<e])
                    if code.hasPrefix(" ") && code.hasSuffix(" ") && code.count > 2 { code = String(code.dropFirst().dropLast()) }
                    var st = style; st.code = true
                    out.append(.run(Run(code.replacingOccurrences(of: "\n", with: " "), st)))
                    i = e + n; continue
                }
                buf.append(String(repeating: "`", count: n)); i += n; continue
            }
            // 图片
            if c == "!", i + 1 < chars.count, chars[i + 1] == "[", let e = findBracketEnd(i + 1), let (src, next) = parseLinkTarget(e + 1) {
                flushBuf()
                let alt = String(chars[(i + 2)..<e])
                if let img = TextUtil.loadImage(src: src, baseDir: baseDir, alt: alt) {
                    out.append(.image(img))
                } else {
                    var st = style; st.link = src
                    out.append(.run(Run(alt.isEmpty ? src : alt, st)))
                }
                i = next; continue
            }
            // 链接
            if c == "[", let e = findBracketEnd(i), let (href, next) = parseLinkTarget(e + 1) {
                flushBuf()
                var st = style; st.link = href
                let inner = inlineTokens(String(chars[(i + 1)..<e]), style: st)
                out.append(contentsOf: inner)
                i = next; continue
            }
            // 自动链接
            if c == "<", let e = chars[i...].firstIndex(of: ">") {
                let inner = String(chars[(i + 1)..<e])
                if inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("mailto:") {
                    flushBuf()
                    var st = style; st.link = inner
                    out.append(.run(Run(inner, st)))
                    i = e + 1; continue
                }
                let lower = inner.lowercased()
                if lower == "br" || lower == "br/" || lower == "br /" { buf.append("\n"); i = e + 1; continue }
                let simple: [String: WritableKeyPath<TextStyle, Bool>] = ["u": \.underline, "b": \.bold, "strong": \.bold,
                                                                          "i": \.italic, "em": \.italic, "s": \.strike, "del": \.strike]
                if let kp = simple[lower] {
                    let close = Array("</\(lower)>")
                    if let ce = findSeq(chars, close, from: e + 1) {
                        flushBuf()
                        var st = style; st[keyPath: kp] = true
                        out.append(contentsOf: inlineTokens(String(chars[(e + 1)..<ce]), style: st))
                        i = ce + close.count; continue
                    }
                }
            }
            // 强调
            if c == "*" || c == "_" || c == "~" {
                let n = chars[i...].prefix(while: { $0 == c }).count
                let nextChar = i + n < chars.count ? chars[i + n] : " "
                let prevChar: Character = i > 0 ? chars[i - 1] : " "
                let intraword = c == "_" && (prevChar.isLetter || prevChar.isNumber)
                if nextChar != " " && !intraword {
                    if c == "~" && n == 2, let e = findClose(["~", "~"], from: i + 2) {
                        flushBuf()
                        var st = style; st.strike = true
                        out.append(contentsOf: inlineTokens(String(chars[(i + 2)..<e]), style: st))
                        i = e + 2; continue
                    }
                    if c != "~" && n >= 3, let e = findClose([c, c, c], from: i + 3) {
                        flushBuf()
                        var st = style; st.bold = true; st.italic = true
                        out.append(contentsOf: inlineTokens(String(chars[(i + 3)..<e]), style: st))
                        i = e + 3; continue
                    }
                    if c != "~" && n >= 2, let e = findClose([c, c], from: i + 2) {
                        flushBuf()
                        var st = style; st.bold = true
                        out.append(contentsOf: inlineTokens(String(chars[(i + 2)..<e]), style: st))
                        i = e + 2; continue
                    }
                    if c != "~" && n == 1, let e = findClose([c], from: i + 1) {
                        let after = e + 1 < chars.count ? chars[e + 1] : " "
                        if !(c == "_" && (after.isLetter || after.isNumber)) {
                            flushBuf()
                            var st = style; st.italic = true
                            out.append(contentsOf: inlineTokens(String(chars[(i + 1)..<e]), style: st))
                            i = e + 1; continue
                        }
                    }
                }
                buf.append(String(repeating: c, count: n)); i += n; continue
            }
            // HTML 实体
            if c == "&", let semi = chars[i...].prefix(10).firstIndex(of: ";") {
                let ent = String(chars[i...semi])
                if let decoded = HTMLEntities.decode(ent) { buf.append(decoded); i = semi + 1; continue }
            }
            buf.append(c)
            i += 1
        }
        flushBuf()
        return out
    }

    func findSeq(_ chars: [Character], _ seq: [Character], from: Int) -> Int? {
        guard seq.count <= chars.count else { return nil }
        var j = from
        while j + seq.count <= chars.count {
            if Array(chars[j..<(j + seq.count)]).map({ Character($0.lowercased()) }) == seq { return j }
            j += 1
        }
        return nil
    }
}

private extension Array where Element == MarkdownParser.Token {
    var lastText: Character? {
        for t in reversed() { if case .run(let r) = t, let c = r.text.last { return c } }
        return nil
    }
}

// MARK: 写出

public final class MarkdownWriter {
    let assetsDirName: String
    let embed: Bool
    public private(set) var assets: [(String, Data)] = []

    public init(assetsDirName: String = "assets", embed: Bool = false) {
        self.assetsDirName = assetsDirName; self.embed = embed
    }

    public func render(_ doc: Document) -> String {
        var parts: [String] = []
        for b in doc.blocks { parts.append(block(b)) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    }

    func block(_ b: Block) -> String {
        switch b {
        case .heading(let level, let c):
            return String(repeating: "#", count: max(1, min(6, level))) + " " + inline(c).replacingOccurrences(of: "\n", with: " ")
        case .paragraph(let c):
            return escapeLineStart(inline(c))
        case .list(let ordered, let start, let items):
            var lines: [String] = []
            for (idx, item) in items.enumerated() {
                var marker = ordered ? "\(start + idx). " : "- "
                if let ch = item.checked { marker += ch ? "[x] " : "[ ] " }
                let pad = String(repeating: " ", count: ordered ? "\(start + idx). ".count : 2)
                var inner = ""
                for (bi, ib) in item.blocks.enumerated() {
                    if bi > 0 {
                        if case .list = ib { inner += "\n" } else { inner += "\n\n" }
                    }
                    inner += block(ib)
                }
                let innerLines = inner.isEmpty ? [""] : inner.components(separatedBy: "\n")
                lines.append(marker + innerLines[0])
                for l in innerLines.dropFirst() { lines.append(l.isEmpty ? "" : pad + l) }
            }
            return lines.joined(separator: "\n")
        case .table(let t):
            let t = t.padded()
            guard t.columnCount > 0, !t.rows.isEmpty else { return "" }
            func row(_ r: [TableCell]) -> String {
                "| " + r.map { inline($0.content, hardBreak: "<br>").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: " | ") + " |"
            }
            var lines = [row(t.rows[0]), "|" + Array(repeating: " --- |", count: t.columnCount).joined()]
            lines.append(contentsOf: t.rows.dropFirst().map(row))
            return lines.joined(separator: "\n")
        case .code(let text, let lang):
            let fence = text.contains("```") ? "~~~~" : "```"
            return fence + (lang ?? "") + "\n" + text + "\n" + fence
        case .quote(let inner):
            return inner.map { block($0) }.joined(separator: "\n\n")
                .components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        case .image(let img):
            return "![\(img.alt.replacingOccurrences(of: "]", with: ""))](\(imageRef(img)))"
        case .horizontalRule:
            return "---"
        case .pageBreak:
            return "<div style=\"page-break-after: always;\"></div>"
        }
    }

    func imageRef(_ img: ImageData) -> String {
        if embed { return TextUtil.base64DataURI(img) }
        let name = "image-\(assets.count + 1).\(img.fileExtension)"
        assets.append((name, img.data))
        let dir = assetsDirName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetsDirName
        return "\(dir)/\(name)"
    }

    func escapeLineStart(_ s: String) -> String {
        s.components(separatedBy: "\n").map { line -> String in
            if let f = line.first, "#>+-=".contains(f) { return "\\" + line }
            if line.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil, let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }) {
                return String(line[..<dot]) + "\\" + String(line[dot...])
            }
            return line
        }.joined(separator: "\n")
    }

    static func escapeText(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            let prev: Character = i > 0 ? chars[i - 1] : " "
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            switch c {
            case "\\", "`", "*": out.append("\\")
            case "_":
                // 单词内部的下划线（snake_case）不会触发强调，无需转义
                if !(prev.isLetter || prev.isNumber) || !(next.isLetter || next.isNumber) { out.append("\\") }
            case "[": if s.contains("](") { out.append("\\") }
            case "<": if next.isLetter || next == "/" || next == "!" { out.append("\\") }
            case "~": if next == "~" || prev == "~" { out.append("\\") }
            default: break
            }
            out.append(c)
        }
        return out
    }

    public func inline(_ runs: [Run], hardBreak: String = "  \n") -> String {
        var out = ""
        for r in runs.normalized() {
            var t = r.style.code ? r.text : MarkdownWriter.escapeText(r.text)
            if r.style.code {
                let fence = t.contains("`") ? "`` " : "`"
                t = fence + t + (fence == "`" ? "`" : " ``")
            }
            // 把首尾空白挪到标记外，否则 ** text** 不会被识别
            let lead = String(t.prefix(while: { $0 == " " || $0 == "\n" }))
            let trail = String(t.reversed().prefix(while: { $0 == " " || $0 == "\n" }).reversed())
            var core = String(t.dropFirst(lead.count).dropLast(trail.count))
            if core.isEmpty { out += t.replacingOccurrences(of: "\n", with: hardBreak); continue }
            if r.style.strike { core = "~~\(core)~~" }
            if r.style.italic { core = "*\(core)*" }
            if r.style.bold { core = "**\(core)**" }
            if r.style.underline { core = "<u>\(core)</u>" }
            if let link = r.style.link { core = "[\(core)](\(link.replacingOccurrences(of: " ", with: "%20")))" }
            out += lead + core + trail
        }
        return out.replacingOccurrences(of: "\n", with: hardBreak)
    }
}
