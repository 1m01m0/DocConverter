import Foundation

// MARK: - 中间表示（IR）
// 所有格式都先读成 Document，再从 Document 写出，N 个读取器 + M 个写入器即可实现 N×M 互转。

public struct TextStyle: Hashable {
    public var bold = false
    public var italic = false
    public var underline = false
    public var strike = false
    public var code = false
    public var link: String? = nil

    public init(bold: Bool = false, italic: Bool = false, underline: Bool = false,
                strike: Bool = false, code: Bool = false, link: String? = nil) {
        self.bold = bold; self.italic = italic; self.underline = underline
        self.strike = strike; self.code = code; self.link = link
    }
    public static let plain = TextStyle()
}

/// 一段带样式的文字。文字中的 "\n" 表示段内换行。
public struct Run: Hashable {
    public var text: String
    public var style: TextStyle
    public init(_ text: String, _ style: TextStyle = .plain) {
        self.text = text; self.style = style
    }
}

public typealias Inlines = [Run]

public extension Array where Element == Run {
    var plainText: String { map(\.text).joined() }
    var isBlank: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 合并相邻同样式的 run
    func normalized() -> [Run] {
        var out: [Run] = []
        for r in self where !r.text.isEmpty {
            if let last = out.last, last.style == r.style {
                out[out.count - 1].text += r.text
            } else {
                out.append(r)
            }
        }
        return out
    }

    func trimmed() -> [Run] {
        var runs = self.normalized()
        while let f = runs.first, f.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { runs.removeFirst() }
        while let l = runs.last, l.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { runs.removeLast() }
        if !runs.isEmpty {
            runs[0].text = String(runs[0].text.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" }))
            let li = runs.count - 1
            while let c = runs[li].text.last, c == " " || c == "\t" || c == "\n" { runs[li].text.removeLast() }
        }
        return runs
    }
}

public struct ImageData: Hashable {
    public var data: Data
    public var mime: String          // image/png, image/jpeg, image/gif ...
    public var alt: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(data: Data, mime: String? = nil, alt: String = "") {
        self.data = data
        let info = ImageInfo.detect(data)
        self.mime = mime ?? info?.mime ?? "image/png"
        self.alt = alt
        self.pixelWidth = info?.width ?? 0
        self.pixelHeight = info?.height ?? 0
    }

    public var fileExtension: String {
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "image/svg+xml": return "svg"
        case "image/webp": return "webp"
        default: return "png"
        }
    }
}

public struct TableCell: Hashable {
    public var content: Inlines
    public init(_ content: Inlines) { self.content = content }
    public init(text: String) { self.content = text.isEmpty ? [] : [Run(text)] }
    public var text: String { content.plainText }
}

public struct Table: Hashable {
    public var rows: [[TableCell]]
    public var headerRows: Int
    public var name: String?           // 来自 Excel 工作表名等
    public init(rows: [[TableCell]], headerRows: Int = 1, name: String? = nil) {
        self.rows = rows; self.headerRows = headerRows; self.name = name
    }
    public var columnCount: Int { rows.map(\.count).max() ?? 0 }

    /// 补齐每行列数
    public func padded() -> Table {
        let n = columnCount
        var t = self
        t.rows = rows.map { $0.count < n ? $0 + Array(repeating: TableCell([]), count: n - $0.count) : $0 }
        return t
    }
}

public struct ListItem: Hashable {
    public var blocks: [Block]
    public var checked: Bool? = nil     // 任务列表
    public init(_ blocks: [Block], checked: Bool? = nil) { self.blocks = blocks; self.checked = checked }
}

public indirect enum Block: Hashable {
    case heading(level: Int, content: Inlines)
    case paragraph(Inlines)
    case list(ordered: Bool, start: Int, items: [ListItem])
    case table(Table)
    case code(text: String, language: String?)
    case quote([Block])
    case image(ImageData)
    case horizontalRule
    case pageBreak           // 分页 / 分幻灯片 / 分工作表
}

public struct Document: Hashable {
    public var title: String?
    public var author: String?
    public var blocks: [Block]
    public init(title: String? = nil, author: String? = nil, blocks: [Block] = []) {
        self.title = title; self.author = author; self.blocks = blocks
    }

    /// 所有表格（递归）
    public var allTables: [Table] {
        var out: [Table] = []
        func walk(_ bs: [Block]) {
            for b in bs {
                switch b {
                case .table(let t): out.append(t)
                case .quote(let inner): walk(inner)
                case .list(_, _, let items): items.forEach { walk($0.blocks) }
                default: break
                }
            }
        }
        walk(blocks)
        return out
    }

    /// 所有表格；没有名称的表格用其前面最近的标题命名（用于 Excel 工作表名、CSV 文件名）
    public var namedTables: [Table] {
        var out: [Table] = []
        var lastHeading: String? = nil
        func walk(_ bs: [Block]) {
            for b in bs {
                switch b {
                case .heading(_, let c): lastHeading = c.plainText
                case .table(var t):
                    if t.name == nil || t.name?.isEmpty == true { t.name = lastHeading }
                    out.append(t)
                    lastHeading = nil
                case .quote(let inner): walk(inner)
                case .list(_, _, let items): items.forEach { walk($0.blocks) }
                default: break
                }
            }
        }
        walk(blocks)
        return out
    }

    /// 文档标题：显式标题 > 第一个标题块
    public var effectiveTitle: String? {
        if let t = title, !t.isEmpty { return t }
        for b in blocks { if case .heading(_, let c) = b { return c.plainText } }
        return nil
    }
}

// MARK: - 格式

public enum Format: String, CaseIterable, Identifiable, Codable {
    case pdf, docx, doc, pptx, xlsx, md, html, txt, csv, tsv, json, rtf, odt, epub, tex, png, jpg

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "Word (.docx)"
        case .doc: return "Word 97 (.doc)"
        case .pptx: return "PowerPoint (.pptx)"
        case .xlsx: return "Excel (.xlsx)"
        case .md: return "Markdown"
        case .html: return "HTML"
        case .txt: return L.plainText
        case .csv: return "CSV"
        case .tsv: return "TSV"
        case .json: return "JSON"
        case .rtf: return "RTF"
        case .odt: return "OpenDocument (.odt)"
        case .epub: return L.epubBook
        case .tex: return "LaTeX"
        case .png: return L.pngImage
        case .jpg: return L.jpegImage
        }
    }

    public var shortName: String {
        switch self {
        case .docx: return "Word"
        case .doc: return "DOC"
        case .pptx: return "PPT"
        case .xlsx: return "Excel"
        case .md: return "Markdown"
        case .txt: return "TXT"
        case .tex: return "LaTeX"
        default: return rawValue.uppercased()
        }
    }

    public var fileExtension: String { rawValue }

    public static func from(extension ext: String) -> Format? {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "docx", "docm", "dotx": return .docx
        case "doc": return .doc
        case "pptx", "pptm", "potx", "ppsx": return .pptx
        case "xlsx", "xlsm", "xltx": return .xlsx
        case "md", "markdown", "mdown", "mkd": return .md
        case "html", "htm", "xhtml": return .html
        case "txt", "text", "log": return .txt
        case "csv": return .csv
        case "tsv", "tab": return .tsv
        case "json": return .json
        case "rtf": return .rtf
        case "odt": return .odt
        case "epub": return .epub
        case "tex", "latex": return .tex
        case "png": return .png
        case "jpg", "jpeg": return .jpg
        default: return nil
        }
    }

    public static func from(url: URL) -> Format? { from(extension: url.pathExtension) }
}

// MARK: - 选项

public enum PageSize: String, CaseIterable, Identifiable, Codable {
    case a4, letter, a3, a5
    public var id: String { rawValue }
    /// 单位：pt
    public var size: (width: Double, height: Double) {
        switch self {
        case .a4: return (595.28, 841.89)
        case .letter: return (612, 792)
        case .a3: return (841.89, 1190.55)
        case .a5: return (419.53, 595.28)
        }
    }
    public var displayName: String {
        switch self { case .a4: return "A4"; case .letter: return "Letter"; case .a3: return "A3"; case .a5: return "A5" }
    }
}

public enum PDFReadMode: String, CaseIterable, Identifiable, Codable {
    case text          // 提取文字与结构（可编辑）
    case pageImages    // 每页渲染为图片（保留版式，不可编辑）
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .text: return L.pdfModeText; case .pageImages: return L.pdfModeImages }
    }
}

public struct ConversionOptions: Codable, Equatable {
    public var pageSize: PageSize = .a4
    public var landscape = false
    public var marginPt: Double = 56          // ≈ 2 cm
    public var baseFontSize: Double = 11
    public var pdfReadMode: PDFReadMode = .text
    public var slideSplitLevel: Int = 2       // 按 H1/H2 拆分幻灯片
    public var includeSpeakerNotes = false
    public var imageDPI: Double = 150
    public var useLibreOffice = false         // 检测到 LibreOffice 时可开启高保真转换
    public var ocrScannedPages = true         // PDF 中没有文字层的页面（扫描件）用系统 OCR 识别
    public var embedImagesInMarkdown = false  // Markdown 中图片以 data URI 内嵌，否则另存到 _assets 目录

    public init() {}

    public var pageWidth: Double { landscape ? pageSize.size.height : pageSize.size.width }
    public var pageHeight: Double { landscape ? pageSize.size.width : pageSize.size.height }
}

// MARK: - 错误

public enum ConversionError: LocalizedError {
    case unsupportedInput(String)
    case unsupportedOutput(String)
    case invalidFile(String)
    case emptyDocument
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput(let s): return L.errUnsupportedInput(s.isEmpty ? L.noExtension : s)
        case .unsupportedOutput(let s): return L.errUnsupportedOutput(s)
        case .invalidFile(let s): return L.errInvalidFile(s)
        case .emptyDocument: return L.errEmptyDocument
        case .toolFailed(let s): return L.errFailed(s)
        }
    }
}
