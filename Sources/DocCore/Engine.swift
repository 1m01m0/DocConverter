import Foundation

// MARK: - 读写器协议

public protocol DocumentReader {
    var formats: [Format] { get }
    func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document
}

public protocol DocumentWriter {
    var formats: [Format] { get }
    /// 写出到 url。可能额外生成附属文件（如多工作表 CSV、Markdown 图片目录），返回全部生成的文件。
    func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions) throws -> [URL]
}

/// 绕过中间表示的直接转换（例如 LibreOffice 高保真转换）
public protocol DirectConverter {
    var name: String { get }
    func canConvert(from: Format, to: Format, options: ConversionOptions) -> Bool
    func convert(_ input: URL, from: Format, to: Format, output: URL, options: ConversionOptions) throws -> [URL]
}

// MARK: - 转换引擎

public final class ConversionEngine {
    public static let shared = ConversionEngine()

    private var readers: [Format: DocumentReader] = [:]
    private var writers: [Format: DocumentWriter] = [:]
    private var directs: [DirectConverter] = []
    private let lock = NSLock()

    public init(registerCore: Bool = true) {
        if registerCore { CoreFormats.register(on: self) }
    }

    public func register(reader: DocumentReader) {
        lock.lock(); defer { lock.unlock() }
        for f in reader.formats { readers[f] = reader }
    }

    public func register(writer: DocumentWriter) {
        lock.lock(); defer { lock.unlock() }
        for f in writer.formats { writers[f] = writer }
    }

    public func register(direct: DirectConverter) {
        lock.lock(); defer { lock.unlock() }
        directs.append(direct)
    }

    public var inputFormats: [Format] { Format.allCases.filter { readers[$0] != nil } }
    public var outputFormats: [Format] { Format.allCases.filter { writers[$0] != nil } }

    public func canRead(_ f: Format) -> Bool { readers[f] != nil }

    public func outputFormats(for input: Format, options: ConversionOptions = ConversionOptions()) -> [Format] {
        Format.allCases.filter { $0 != input && canConvert(from: input, to: $0, options: options) }
    }

    public func canConvert(from: Format, to: Format, options: ConversionOptions = ConversionOptions()) -> Bool {
        if from == to { return false }
        if readers[from] != nil && writers[to] != nil { return true }
        return directs.contains { $0.canConvert(from: from, to: to, options: options) }
    }

    /// 只读取为中间表示（用于预览 / 测试）
    public func read(_ url: URL, options: ConversionOptions = ConversionOptions()) throws -> Document {
        guard let f = Format.from(url: url) else { throw ConversionError.unsupportedInput(url.pathExtension) }
        guard let r = readers[f] else { throw ConversionError.unsupportedInput(f.displayName) }
        var doc = try r.read(url, format: f, options: options)
        if doc.title == nil || doc.title?.isEmpty == true {
            doc.title = url.deletingPathExtension().lastPathComponent
        }
        return doc
    }

    public func write(_ doc: Document, to url: URL, format: Format, options: ConversionOptions = ConversionOptions()) throws -> [URL] {
        guard let w = writers[format] else { throw ConversionError.unsupportedOutput(format.displayName) }
        return try w.write(doc, to: url, format: format, options: options)
    }

    /// 转换单个文件。outputDirectory 为 nil 时输出到源文件所在目录。不会覆盖已有文件。
    @discardableResult
    public func convert(_ input: URL, to target: Format, outputDirectory: URL? = nil,
                        options: ConversionOptions = ConversionOptions()) throws -> [URL] {
        guard let source = Format.from(url: input) else { throw ConversionError.unsupportedInput(input.pathExtension) }
        let dir = outputDirectory ?? input.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = input.deletingPathExtension().lastPathComponent
        let out = ConversionEngine.uniqueURL(in: dir, base: base, ext: target.fileExtension)

        // 直接转换器优先（例如 PDF 直接栅格化为图片、开启后的 LibreOffice 高保真转换）
        if let d = directs.first(where: { $0.canConvert(from: source, to: target, options: options) }) {
            return try d.convert(input, from: source, to: target, output: out, options: options)
        }
        let doc = try read(input, options: options)
        if doc.blocks.isEmpty { throw ConversionError.emptyDocument }
        return try write(doc, to: out, format: target, options: options)
    }

    public static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var i = 1
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(i))").appendingPathExtension(ext)
            i += 1
        }
        return url
    }

    public static func uniqueDirectory(in dir: URL, base: String) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent(base, isDirectory: true)
        var i = 1
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(i))", isDirectory: true)
            i += 1
        }
        return url
    }
}

// MARK: - 核心（跨平台）格式注册

public enum CoreFormats {
    public static func register(on engine: ConversionEngine) {
        engine.register(reader: PlainTextFormat())
        engine.register(writer: PlainTextFormat())
        engine.register(reader: MarkdownFormat())
        engine.register(writer: MarkdownFormat())
        engine.register(reader: HTMLFormat())
        engine.register(writer: HTMLFormat())
        engine.register(reader: CSVFormat())
        engine.register(writer: CSVFormat())
        engine.register(reader: JSONFormat())
        engine.register(writer: JSONFormat())
        engine.register(reader: DOCXFormat())
        engine.register(writer: DOCXFormat())
        engine.register(reader: XLSXFormat())
        engine.register(writer: XLSXFormat())
        engine.register(reader: PPTXFormat())
        engine.register(writer: PPTXFormat())
        engine.register(reader: EPUBFormat())
        engine.register(writer: EPUBFormat())
        engine.register(writer: LaTeXFormat())
        engine.register(reader: ImageInputFormat())
    }
}

/// 图片作为输入：生成只含一张图片的文档（图片 → PDF / Word / PPT）
struct ImageInputFormat: DocumentReader {
    var formats: [Format] { [.png, .jpg] }
    func read(_ url: URL, format: Format, options: ConversionOptions) throws -> Document {
        let data = try Data(contentsOf: url)
        // 只检查文件头：随机数据、改了扩展名的文件等直接报错，而不是生成一张空白图
        guard ImageInfo.detect(data) != nil else { throw ConversionError.invalidFile(url.lastPathComponent) }
        let img = ImageData(data: data, alt: url.deletingPathExtension().lastPathComponent)
        return Document(title: url.deletingPathExtension().lastPathComponent, blocks: [.image(img)])
    }
}
