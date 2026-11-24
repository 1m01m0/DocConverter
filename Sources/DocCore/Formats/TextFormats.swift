import Foundation

// MARK: - 纯文本

public struct PlainTextFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.txt] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let text = TextDecoder.normalizeNewlines(try TextDecoder.read(url))
        var blocks: [Block] = []
        for page in text.components(separatedBy: "\u{000C}") {
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            var para: [String] = []
            func flush() {
                if !para.isEmpty { blocks.append(.paragraph([Run(para.joined(separator: "\n"))])) }
                para = []
            }
            for line in page.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { flush() } else { para.append(line.replacingOccurrences(of: "\t", with: "    ").trimmingTrailingSpaces()) }
            }
            flush()
        }
        return Document(blocks: blocks)
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        try Data(PlainTextFormat.render(doc).utf8).write(to: url)
        return [url]
    }

    public static func render(_ doc: Document) -> String {
        doc.blocks.map { block($0, indent: "") }.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    }

    static func block(_ b: Block, indent: String) -> String {
        func ind(_ s: String) -> String { s.components(separatedBy: "\n").map { indent + $0 }.joined(separator: "\n") }
        switch b {
        case .heading(let level, let c):
            let t = c.plainText.replacingOccurrences(of: "\n", with: " ")
            if level == 1 { return ind(t + "\n" + String(repeating: "=", count: max(4, TextUtil.displayWidth(t)))) }
            if level == 2 { return ind(t + "\n" + String(repeating: "-", count: max(4, TextUtil.displayWidth(t)))) }
            return ind(t)
        case .paragraph(let c): return ind(c.plainText)
        case .list(let ordered, let start, let items):
            return items.enumerated().map { i, item in
                var marker = ordered ? "\(start + i). " : "• "
                if let ch = item.checked { marker += ch ? "[x] " : "[ ] " }
                let pad = String(repeating: " ", count: marker.count)
                let inner = item.blocks.map { block($0, indent: "") }.joined(separator: "\n")
                let lines = inner.components(separatedBy: "\n")
                return ([indent + marker + (lines.first ?? "")] + lines.dropFirst().map { indent + pad + $0 }).joined(separator: "\n")
            }.joined(separator: "\n")
        case .table(let t):
            let t = t.padded()
            let texts = t.rows.map { $0.map { $0.text.replacingOccurrences(of: "\n", with: " ") } }
            var widths = Array(repeating: 0, count: t.columnCount)
            for r in texts { for (i, c) in r.enumerated() { widths[i] = min(40, max(widths[i], TextUtil.displayWidth(c))) } }
            var lines: [String] = []
            for (ri, r) in texts.enumerated() {
                let cells = r.enumerated().map { i, c -> String in
                    c + String(repeating: " ", count: max(0, widths[i] - TextUtil.displayWidth(c)))
                }
                lines.append(indent + cells.joined(separator: "  ").trimmingTrailingSpaces())
                if ri == t.headerRows - 1 && t.rows.count > 1 {
                    lines.append(indent + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
                }
            }
            return lines.joined(separator: "\n")
        case .code(let text, _):
            return text.components(separatedBy: "\n").map { indent + "    " + $0 }.joined(separator: "\n")
        case .quote(let inner):
            return inner.map { block($0, indent: "") }.joined(separator: "\n\n")
                .components(separatedBy: "\n").map { indent + "> " + $0 }.joined(separator: "\n")
        case .image(let img): return ind(L.imagePlaceholder(img.alt))
        case .horizontalRule: return ind(String(repeating: "─", count: 24))
        case .pageBreak: return ind(String(repeating: "═", count: 24))
        }
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var s = self
        while let l = s.last, l == " " || l == "\t" { s.removeLast() }
        return s
    }
}

// MARK: - CSV / TSV

public struct CSVFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.csv, .tsv] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let text = TextDecoder.normalizeNewlines(try TextDecoder.read(url))
        let delim: Character = format == .tsv ? "\t" : CSVFormat.detectDelimiter(text)
        let rows = CSVFormat.parse(text, delimiter: delim)
        guard !rows.isEmpty else { return Document(blocks: []) }
        let name = url.deletingPathExtension().lastPathComponent
        let table = Table(rows: rows.map { $0.map { TableCell(text: $0) } }, headerRows: 1, name: name).padded()
        return Document(title: name, blocks: [.table(table)])
    }

    static func detectDelimiter(_ text: String) -> Character {
        let sample = text.prefix(4000).split(separator: "\n").prefix(10)
        var best: Character = ","
        var bestScore = 0
        for d in [",", ";", "\t", "|"] as [Character] {
            let counts = sample.map { line in line.filter { $0 == d }.count }
            guard let f = counts.first, f > 0 else { continue }
            let consistent = counts.filter { $0 == f }.count
            let score = consistent * 10 + f
            if score > bestScore { bestScore = score; best = d }
        }
        return best
    }

    public static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = Array(text)[...]
        while let c = it.popFirst() {
            if inQuotes {
                if c == "\"" {
                    if it.first == "\"" { field.append("\""); it.removeFirst() } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                if c == "\"" && field.isEmpty { inQuotes = true }
                else if c == delimiter { row.append(field); field = "" }
                else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
                else { field.append(c) }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        // 去掉末尾全空行
        while let l = rows.last, l.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
        return rows
    }

    public static func encode(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { r in
            r.map { f -> String in
                if f.contains(delimiter) || f.contains("\"") || f.contains("\n") || f.contains("\r") || f.hasPrefix(" ") || f.hasSuffix(" ") {
                    return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return f
            }.joined(separator: String(delimiter))
        }.joined(separator: "\r\n") + "\r\n"
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let delim: Character = format == .tsv ? "\t" : ","
        var tables = doc.namedTables
        if tables.isEmpty {
            // 非表格文档：每行文字作为一行
            let lines = TextUtil.plainLines(doc.blocks).filter { !$0.isEmpty }
            tables = [Table(rows: lines.map { [TableCell(text: $0)] }, headerRows: 0)]
        }
        func data(_ t: Table) -> Data {
            let rows = t.padded().rows.map { $0.map(\.text) }
            // 带 BOM 的 UTF-8，Excel 打开中文不会乱码
            return Data([0xEF, 0xBB, 0xBF]) + Data(CSVFormat.encode(rows, delimiter: delim).utf8)
        }
        if tables.count == 1 {
            try data(tables[0]).write(to: url)
            return [url]
        }
        var out: [URL] = []
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        for (i, t) in tables.enumerated() {
            let name = TextUtil.safeFileName(t.name ?? L.tableN(i + 1))
            let u = ConversionEngine.uniqueURL(in: dir, base: "\(base)_\(name)", ext: format.fileExtension)
            try data(t).write(to: u)
            out.append(u)
        }
        return out
    }
}

// MARK: - JSON

/// 保持键顺序的 JSON 值
indirect enum JValue {
    case string(String), number(String), bool(Bool), null
    case array([JValue]), object([(String, JValue)])

    func render(_ indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let pad1 = String(repeating: "  ", count: indent + 1)
        switch self {
        case .string(let s): return JValue.quote(s)
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a):
            if a.isEmpty { return "[]" }
            if a.allSatisfy({ if case .array = $0 { return false }; if case .object = $0 { return false }; return true }) {
                return "[" + a.map { $0.render() }.joined(separator: ", ") + "]"
            }
            return "[\n" + a.map { pad1 + $0.render(indent + 1) }.joined(separator: ",\n") + "\n\(pad)]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.map { pad1 + JValue.quote($0.0) + ": " + $0.1.render(indent + 1) }.joined(separator: ",\n") + "\n\(pad)}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
}

public struct JSONFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.json] }
    public init() {}

    // 读取：对象数组 → 表格；{表名: 对象数组} → 多个表格；本工具导出的文档结构 → 还原；其他 → 代码块

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let data = try Data(contentsOf: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw ConversionError.invalidFile(L.invalidJSON)
        }
        let name = url.deletingPathExtension().lastPathComponent
        if let dict = obj as? [String: Any], let blocks = dict["blocks"] as? [[String: Any]] {
            return Document(title: dict["title"] as? String, blocks: blocks.compactMap(decodeBlock))
        }
        if let arr = obj as? [Any], let t = table(from: arr, name: name, orderSource: data) {
            return Document(title: name, blocks: [.table(t)])
        }
        if let dict = obj as? [String: Any], !dict.isEmpty {
            let keys = orderedKeys(data, level: 1) ?? dict.keys.sorted()
            var blocks: [Block] = []
            var allTables = true
            for k in keys {
                guard let arr = dict[k] as? [Any], let t = table(from: arr, name: k, orderSource: nil) else { allTables = false; break }
                blocks.append(.heading(level: 2, content: [Run(k)]))
                blocks.append(.table(t))
            }
            if allTables { return Document(title: name, blocks: blocks) }
        }
        let pretty = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? String(decoding: data, as: UTF8.self)
        return Document(title: name, blocks: [.code(text: pretty, language: "json")])
    }

    /// 尽量保持原始 JSON 中的键顺序（JSONSerialization 会打乱）。level=1 为顶层对象的键，2 为数组内对象的键
    func orderedKeys(_ data: Data, level: Int) -> [String]? {
        let chars = Array(String(decoding: data, as: UTF8.self))
        var keys: [String] = []
        var depth = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                var s = ""
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count { s.append(chars[i]); i += 1 }
                    s.append(chars[i]); i += 1
                }
                i += 1
                var j = i
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j < chars.count && chars[j] == ":" && depth == level {
                    let key = (try? JSONSerialization.jsonObject(with: Data(("\"" + s + "\"").utf8), options: .fragmentsAllowed)) as? String ?? s
                    if !keys.contains(key) { keys.append(key) }
                }
                continue
            }
            if c == "{" || c == "[" { depth += 1 } else if c == "}" || c == "]" { depth -= 1 }
            i += 1
        }
        return keys.isEmpty ? nil : keys
    }

    func table(from arr: [Any], name: String, orderSource: Data?) -> Table? {
        guard !arr.isEmpty else { return nil }
        if arr.allSatisfy({ $0 is [String: Any] }) {
            let objs = arr as! [[String: Any]]
            var header: [String] = []
            let preferred = orderSource.flatMap { orderedKeys($0, level: 2) } ?? []
            for k in preferred where objs.contains(where: { $0[k] != nil }) { header.append(k) }
            for o in objs { for k in o.keys.sorted() where !header.contains(k) { header.append(k) } }
            var rows: [[TableCell]] = [header.map { TableCell(text: $0) }]
            for o in objs { rows.append(header.map { TableCell(text: stringify(o[$0])) }) }
            return Table(rows: rows, headerRows: 1, name: name)
        }
        if arr.allSatisfy({ $0 is [Any] }) {
            let rows = (arr as! [[Any]]).map { $0.map { TableCell(text: stringify($0)) } }
            return Table(rows: rows, headerRows: 1, name: name).padded()
        }
        return nil
    }

    func stringify(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.withoutEscapingSlashes]) { return String(decoding: d, as: UTF8.self) }
        return "\(v)"
    }

    func decodeBlock(_ d: [String: Any]) -> Block? {
        let text = d["text"] as? String ?? ""
        switch d["type"] as? String {
        case "heading": return .heading(level: d["level"] as? Int ?? 1, content: [Run(text)])
        case "paragraph": return .paragraph([Run(text)])
        case "list":
            let items = (d["items"] as? [Any] ?? []).map { item -> ListItem in
                if let s = item as? String { return ListItem([.paragraph([Run(s)])]) }
                if let o = item as? [String: Any] {
                    var bs: [Block] = []
                    if let t = o["text"] as? String { bs.append(.paragraph([Run(t)])) }
                    bs.append(contentsOf: (o["children"] as? [[String: Any]] ?? []).compactMap(decodeBlock))
                    return ListItem(bs, checked: o["checked"] as? Bool)
                }
                return ListItem([])
            }
            return .list(ordered: d["ordered"] as? Bool ?? false, start: d["start"] as? Int ?? 1, items: items)
        case "table":
            var rows: [[TableCell]] = []
            if let h = d["header"] as? [Any], !h.isEmpty { rows.append(h.map { TableCell(text: stringify($0)) }) }
            rows += (d["rows"] as? [[Any]] ?? []).map { $0.map { TableCell(text: stringify($0)) } }
            return .table(Table(rows: rows, headerRows: (d["header"] as? [Any])?.isEmpty == false ? 1 : 0, name: d["name"] as? String).padded())
        case "code": return .code(text: text, language: d["language"] as? String)
        case "quote": return .quote((d["blocks"] as? [[String: Any]] ?? []).compactMap(decodeBlock))
        case "image":
            guard let b64 = d["data"] as? String, let data = Data(base64Encoded: b64) else { return nil }
            return .image(ImageData(data: data, mime: d["mime"] as? String, alt: d["alt"] as? String ?? ""))
        case "hr": return .horizontalRule
        case "pagebreak": return .pageBreak
        default: return text.isEmpty ? nil : .paragraph([Run(text)])
        }
    }

    // 写出

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        let value: JValue
        let tables = doc.allTables
        let onlyTables = !tables.isEmpty && doc.blocks.allSatisfy {
            switch $0 { case .table, .pageBreak, .heading: return true; default: return false }
        }
        if onlyTables {
            if tables.count == 1 { value = records(tables[0]) }
            else {
                var used = Set<String>()
                value = .object(tables.enumerated().map { i, t in
                    var k = t.name ?? L.tableN(i + 1)
                    while used.contains(k) { k += "_\(i + 1)" }
                    used.insert(k)
                    return (k, records(t))
                })
            }
        } else {
            var o: [(String, JValue)] = []
            if let t = doc.effectiveTitle { o.append(("title", .string(t))) }
            o.append(("blocks", .array(doc.blocks.map(encodeBlock))))
            value = .object(o)
        }
        try Data((value.render() + "\n").utf8).write(to: url)
        return [url]
    }

    func cellValue(_ s: String) -> JValue {
        if s.range(of: #"^-?(0|[1-9][0-9]{0,14})(\.[0-9]+)?$"#, options: .regularExpression) != nil { return .number(s) }
        return .string(s)
    }

    func records(_ t: Table) -> JValue {
        let t = t.padded()
        guard t.headerRows > 0, t.rows.count > 1 else { return .array(t.rows.map { .array($0.map { cellValue($0.text) }) }) }
        var header: [String] = []
        for (i, c) in t.rows[0].enumerated() {
            var k = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if k.isEmpty { k = L.columnN(i + 1) }
            var n = 2
            let base = k
            while header.contains(k) { k = "\(base)_\(n)"; n += 1 }
            header.append(k)
        }
        return .array(t.rows.dropFirst().map { r in .object(zip(header, r).map { ($0, cellValue($1.text)) }) })
    }

    func encodeBlock(_ b: Block) -> JValue {
        switch b {
        case .heading(let l, let c): return .object([("type", .string("heading")), ("level", .number("\(l)")), ("text", .string(c.plainText))])
        case .paragraph(let c): return .object([("type", .string("paragraph")), ("text", .string(c.plainText))])
        case .list(let ordered, let start, let items):
            let its: [JValue] = items.map { item in
                var text = ""
                var rest = item.blocks
                if let f = rest.first, case .paragraph(let c) = f { text = c.plainText; rest.removeFirst() }
                if rest.isEmpty && item.checked == nil { return .string(text) }
                var o: [(String, JValue)] = [("text", .string(text))]
                if let ch = item.checked { o.append(("checked", .bool(ch))) }
                if !rest.isEmpty { o.append(("children", .array(rest.map(encodeBlock)))) }
                return .object(o)
            }
            var o: [(String, JValue)] = [("type", .string("list")), ("ordered", .bool(ordered))]
            if ordered && start != 1 { o.append(("start", .number("\(start)"))) }
            o.append(("items", .array(its)))
            return .object(o)
        case .table(let t):
            let t = t.padded()
            var o: [(String, JValue)] = [("type", .string("table"))]
            if let n = t.name { o.append(("name", .string(n))) }
            let head = t.rows.prefix(t.headerRows).first
            o.append(("header", .array((head ?? []).map { .string($0.text) })))
            o.append(("rows", .array(t.rows.dropFirst(head == nil ? 0 : t.headerRows).map { .array($0.map { .string($0.text) }) })))
            return .object(o)
        case .code(let text, let lang):
            var o: [(String, JValue)] = [("type", .string("code"))]
            if let l = lang { o.append(("language", .string(l))) }
            o.append(("text", .string(text)))
            return .object(o)
        case .quote(let inner): return .object([("type", .string("quote")), ("blocks", .array(inner.map(encodeBlock)))])
        case .image(let img):
            return .object([("type", .string("image")), ("alt", .string(img.alt)), ("mime", .string(img.mime)),
                            ("width", .number("\(img.pixelWidth)")), ("height", .number("\(img.pixelHeight)")),
                            ("data", .string(img.data.base64EncodedString()))])
        case .horizontalRule: return .object([("type", .string("hr"))])
        case .pageBreak: return .object([("type", .string("pagebreak"))])
        }
    }
}
