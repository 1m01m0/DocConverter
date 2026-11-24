import Foundation

// MARK: - Excel (.xlsx)
// 读取：每个工作表 → 标题 + 表格；写出：每个表格 → 一个工作表（无表格时把文字逐行写入）

public struct XLSXFormat: DocumentReader, DocumentWriter {
    public var formats: [Format] { [.xlsx] }
    public init() {}

    public func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let zip = try ZipArchive(url: url)
        return try XLSXReader(zip: zip).read()
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL] {
        try XLSXWriter().build(doc).write(to: url)
        return [url]
    }
}

final class XLSXReader {
    let zip: ZipArchive
    var shared: [String] = []
    var dateStyles = Set<Int>()       // cellXfs 索引 → 是否日期格式
    var percentStyles = Set<Int>()

    init(zip: ZipArchive) { self.zip = zip }

    func read() throws -> Document {
        let pkg = Relationships(zip: zip, partPath: "")
        let wbPath = pkg.first(typeSuffix: "/officeDocument") ?? "xl/workbook.xml"
        guard let wb = zip.read(wbPath).flatMap({ XML.parse($0) }), wb.name == "x:workbook" else {
            throw ConversionError.invalidFile(L.missingPart("workbook.xml"))
        }
        let rels = Relationships(zip: zip, partPath: wbPath)
        if let ssPath = rels.first(typeSuffix: "/sharedStrings"), let ss = zip.read(ssPath).flatMap({ XML.parse($0) }) {
            shared = ss.children("x:si").map { si in
                // 跳过拼音注音 rPh
                si.elements.filter { $0.name != "x:rPh" }.map { $0.textContent }.joined()
            }
        }
        if let stPath = rels.first(typeSuffix: "/styles"), let st = zip.read(stPath).flatMap({ XML.parse($0) }) { loadStyles(st) }
        let date1904 = wb.first("x:workbookPr").map { ($0["date1904"] ?? "0") == "1" || $0["date1904"] == "true" } ?? false

        var blocks: [Block] = []
        let sheets = wb.first("x:sheets")?.children("x:sheet") ?? []
        for sh in sheets {
            if sh["state"] == "hidden" || sh["state"] == "veryHidden" { continue }
            guard let rid = sh["r:id"], let path = rels.targets[rid], let xml = zip.read(path).flatMap({ XML.parse($0) }) else { continue }
            let name = sh["name"] ?? "Sheet"
            let rows = parseSheet(xml, date1904: date1904)
            guard !rows.isEmpty else { continue }
            if !blocks.isEmpty { blocks.append(.pageBreak) }
            if sheets.count > 1 { blocks.append(.heading(level: 2, content: [Run(name)])) }
            blocks.append(.table(Table(rows: rows.map { $0.map { TableCell(text: $0) } }, headerRows: 1, name: name)))
        }
        var doc = Document(blocks: blocks)
        if let core = zip.read("docProps/core.xml").flatMap({ XML.parse($0) }),
           let t = core.first("dc:title")?.textContent, !t.isEmpty { doc.title = t }
        return doc
    }

    func loadStyles(_ st: XNode) {
        var customDate = Set<Int>()
        var customPercent = Set<Int>()
        for nf in st.first("x:numFmts")?.children("x:numFmt") ?? [] {
            guard let id = Int(nf["numFmtId"] ?? ""), let code = nf["formatCode"]?.lowercased() else { continue }
            // 去掉引号内文字和颜色/条件后判断是否包含日期占位符
            let stripped = code.replacingOccurrences(of: #"\"[^\"]*\"|\[[^\]]*\]"#, with: "", options: .regularExpression)
            if stripped.contains("y") || stripped.contains("d") || (stripped.contains("m") && !stripped.contains("0")) || stripped.contains("h:") { customDate.insert(id) }
            if stripped.contains("%") { customPercent.insert(id) }
        }
        let builtinDate: Set<Int> = Set(14...22).union(45...47).union([27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 50, 51, 52, 53, 54, 55, 56, 57, 58])
        for (i, xf) in (st.first("x:cellXfs")?.children("x:xf") ?? []).enumerated() {
            let id = Int(xf["numFmtId"] ?? "0") ?? 0
            if builtinDate.contains(id) || customDate.contains(id) { dateStyles.insert(i) }
            if id == 9 || id == 10 || customPercent.contains(id) { percentStyles.insert(i) }
        }
    }

    static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for c in ref.uppercased() {
            guard let a = c.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return n - 1
    }

    func parseSheet(_ xml: XNode, date1904: Bool) -> [[String]] {
        var grid: [Int: [Int: String]] = [:]
        var maxCol = -1
        var rowIdx = -1
        for row in xml.first("x:sheetData")?.children("x:row") ?? [] {
            rowIdx = (Int(row["r"] ?? "") ?? (rowIdx + 2)) - 1
            var colIdx = -1
            for c in row.children("x:c") {
                colIdx = c["r"].map { XLSXReader.columnIndex($0) } ?? (colIdx + 1)
                let t = c["t"] ?? "n"
                let v = c.child("x:v")?.textContent ?? ""
                var text: String
                switch t {
                case "s": text = Int(v).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
                case "inlineStr": text = c.child("x:is").map { $0.elements.filter { $0.name != "x:rPh" }.map(\.textContent).joined() } ?? ""
                case "b": text = v == "1" ? "TRUE" : "FALSE"
                case "e", "str": text = v
                default:
                    let s = Int(c["s"] ?? "0") ?? 0
                    text = formatNumber(v, style: s, date1904: date1904)
                }
                if text.isEmpty { continue }
                grid[rowIdx, default: [:]][colIdx] = text
                maxCol = max(maxCol, colIdx)
            }
        }
        guard maxCol >= 0, let maxRow = grid.keys.max() else { return [] }
        let minRow = grid.keys.min() ?? 0
        // 去掉左侧全空列
        let minCol = grid.values.flatMap(\.keys).min() ?? 0
        var rows: [[String]] = []
        for r in minRow...maxRow {
            let line = grid[r] ?? [:]
            rows.append((minCol...maxCol).map { line[$0] ?? "" })
        }
        return rows
    }

    func formatNumber(_ v: String, style: Int, date1904: Bool) -> String {
        guard let d = Double(v) else { return v }
        if dateStyles.contains(style) {
            let base = date1904 ? -24107.0 : -25569.0     // 相对 1970-01-01 的天数
            let secs = (d + base) * 86400
            let date = Date(timeIntervalSince1970: secs.rounded())
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            if d < 1 { f.dateFormat = "HH:mm:ss" }
            else if d.truncatingRemainder(dividingBy: 1) == 0 { f.dateFormat = "yyyy-MM-dd" }
            else { f.dateFormat = "yyyy-MM-dd HH:mm" }
            return f.string(from: date)
        }
        if percentStyles.contains(style) {
            return XLSXReader.trimNumber(d * 100) + "%"
        }
        return XLSXReader.trimNumber(d)
    }

    static func trimNumber(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        var s = String(format: "%.10g", d)
        if s.contains("e") { return s }
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        return s
    }
}

final class XLSXWriter {
    func build(_ doc: Document) -> Data {
        var tables = doc.namedTables
        if tables.isEmpty {
            let lines = TextUtil.plainLines(doc.blocks)
            tables = [Table(rows: lines.map { [TableCell(text: $0)] }, headerRows: 0, name: L.sheetContent)]
        }
        // 工作表名：唯一、≤31 字符、去掉非法字符
        var names: [String] = []
        for (i, t) in tables.enumerated() {
            var n = (t.name ?? "Sheet\(i + 1)").components(separatedBy: CharacterSet(charactersIn: "[]:*?/\\")).joined()
            n = String(n.prefix(31)).trimmingCharacters(in: CharacterSet(charactersIn: "' "))
            if n.isEmpty { n = "Sheet\(i + 1)" }
            var candidate = n
            var k = 2
            while names.contains(where: { $0.lowercased() == candidate.lowercased() }) {
                candidate = String(n.prefix(27)) + " (\(k))"; k += 1
            }
            names.append(candidate)
        }

        let zip = ZipWriter()
        var overrides = ""
        var sheetEntries = ""
        var wbRels = ""
        for i in tables.indices {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            sheetEntries += "<sheet name=\"\(XML.escape(names[i]))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            wbRels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
            zip.add("xl/worksheets/sheet\(i + 1).xml", sheetXML(tables[i]))
        }
        let n = tables.count
        wbRels += "<Relationship Id=\"rId\(n + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"

        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(overrides)<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
        """)
        zip.add("docProps/core.xml", OOXMLCommon.coreXML(title: doc.effectiveTitle, author: doc.author))
        zip.add("docProps/app.xml", OOXMLCommon.appXML())
        zip.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="16000"/></bookViews><sheets>\(sheetEntries)</sheets></workbook>
        """)
        zip.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(wbRels)</Relationships>
        """)
        zip.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD0D0D0"/></left><right style="thin"><color rgb="FFD0D0D0"/></right><top style="thin"><color rgb="FFD0D0D0"/></top><bottom style="thin"><color rgb="FFD0D0D0"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)
        return zip.finish()
    }

    static func columnName(_ i: Int) -> String {
        var n = i + 1
        var s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    /// 只把"看起来就是数字"的文本写成数值（保留 007、超长编号、电话号码等原样）
    static func numericValue(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t == s, !t.isEmpty, t.count <= 15 else { return nil }
        guard t.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return t
    }

    func sheetXML(_ t: Table) -> String {
        let t = t.padded()
        let cols = t.columnCount
        var widths = Array(repeating: 8.0, count: max(cols, 1))
        for r in t.rows.prefix(200) {
            for (i, c) in r.enumerated() {
                let w = c.text.components(separatedBy: "\n").map { Double(TextUtil.displayWidth($0)) }.max() ?? 0
                widths[i] = min(60, max(widths[i], w + 2))
            }
        }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        if t.headerRows > 0 && t.rows.count > 1 {
            x += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"\(t.headerRows)\" topLeftCell=\"A\(t.headerRows + 1)\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
        } else {
            x += "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
        }
        x += "<sheetFormatPr defaultRowHeight=\"15\"/>"
        if cols > 0 {
            x += "<cols>" + widths.enumerated().map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\(String(format: "%.1f", $0.element))\" customWidth=\"1\"/>" }.joined() + "</cols>"
        }
        x += "<sheetData>"
        let bordered = t.columnCount > 1 || t.headerRows > 0
        for (ri, row) in t.rows.enumerated() {
            x += "<row r=\"\(ri + 1)\">"
            for (ci, cell) in row.enumerated() {
                let ref = "\(XLSXWriter.columnName(ci))\(ri + 1)"
                let style = ri < t.headerRows ? 1 : (bordered ? 2 : 0)
                let s = style > 0 ? " s=\"\(style)\"" : ""
                let text = cell.text
                if text.isEmpty {
                    if style > 0 { x += "<c r=\"\(ref)\"\(s)/>" }
                } else if ri >= t.headerRows, let num = XLSXWriter.numericValue(text) {
                    x += "<c r=\"\(ref)\"\(s)><v>\(num)</v></c>"
                } else {
                    x += "<c r=\"\(ref)\"\(s) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XML.escape(String(text.prefix(32767))))</t></is></c>"
                }
            }
            x += "</row>"
        }
        x += "</sheetData>"
        if t.headerRows > 0 && t.rows.count > 1 && cols > 0 {
            x += "<autoFilter ref=\"A1:\(XLSXWriter.columnName(cols - 1))\(t.rows.count)\"/>"
        }
        x += "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/></worksheet>"
        return x
    }
}
