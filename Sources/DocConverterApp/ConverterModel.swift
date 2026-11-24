import SwiftUI
import AppKit
import DocCore
import DocCoreMac

// MARK: - 转换任务

final class Job: ObservableObject, Identifiable {
    enum Status: Equatable {
        case waiting, running, done([URL]), failed(String), skipped(String)
    }
    let id = UUID()
    let url: URL
    let format: Format?
    let size: Int64
    @Published var status: Status = .waiting

    init(url: URL) {
        self.url = url
        self.format = Format.from(url: url)
        self.size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    var name: String { url.lastPathComponent }
    var isFinished: Bool {
        switch status { case .done, .failed, .skipped: return true; default: return false }
    }
}

// MARK: - 界面状态与转换调度

final class ConverterModel: ObservableObject {
    enum OutputLocation: String, CaseIterable, Identifiable {
        case sameAsSource, custom
        var id: String { rawValue }
        var title: String { self == .sameAsSource ? L.sameAsSource : L.customFolder }
    }

    let engine: ConversionEngine
    @Published var jobs: [Job] = []
    @Published var target: Format { didSet { save() } }
    @Published var options: ConversionOptions { didSet { save() } }
    @Published var outputLocation: OutputLocation { didSet { save() } }
    @Published var customFolder: URL? { didSet { save() } }
    @Published var isConverting = false
    @Published var completed = 0
    @Published var totalToConvert = 0
    @Published var lastOutputs: [URL] = []

    let libreOfficeAvailable = LibreOfficeConverter.isAvailable
    private let queue = DispatchQueue(label: "docconverter.convert", qos: .userInitiated)
    private let defaults = UserDefaults.standard

    init() {
        engine = ConversionEngine.shared
        MacFormats.register(on: engine)
        target = Format(rawValue: defaults.string(forKey: "target") ?? "") ?? .pdf
        if let d = defaults.data(forKey: "options"), let o = try? JSONDecoder().decode(ConversionOptions.self, from: d) {
            options = o
        } else {
            options = ConversionOptions()
        }
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .sameAsSource
        customFolder = defaults.string(forKey: "customFolder").map { URL(fileURLWithPath: $0) }
        if !libreOfficeAvailable { options.useLibreOffice = false }
    }

    private func save() {
        defaults.set(target.rawValue, forKey: "target")
        if let d = try? JSONEncoder().encode(options) { defaults.set(d, forKey: "options") }
        defaults.set(outputLocation.rawValue, forKey: "outputLocation")
        defaults.set(customFolder?.path, forKey: "customFolder")
    }

    // MARK: 文件

    var supportedExtensions: [String] {
        engine.inputFormats.flatMap { f -> [String] in
            switch f {
            case .md: return ["md", "markdown"]
            case .html: return ["html", "htm"]
            case .jpg: return ["jpg", "jpeg"]
            default: return [f.fileExtension]
            }
        }
    }

    /// 添加文件（文件夹会展开其中支持的文件），返回不支持的文件名
    @discardableResult
    func add(_ urls: [URL]) -> [String] {
        var rejected: [String] = []
        var existing = Set(jobs.map { $0.url.standardizedFileURL })
        let fm = FileManager.default
        func addOne(_ u: URL) {
            let std = u.standardizedFileURL
            guard !existing.contains(std) else { return }
            if let f = Format.from(url: u), engine.canRead(f) {
                jobs.append(Job(url: u)); existing.insert(std)
            } else {
                rejected.append(u.lastPathComponent)
            }
        }
        for u in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for i in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where Format.from(url: i).map(engine.canRead) == true {
                    addOne(i)
                }
            } else {
                addOne(u)
            }
        }
        if let first = jobs.first?.format, jobs.count == urls.count, first == target {
            // 第一次拖入的文件与目标格式相同，自动换一个合理的目标
            target = engine.outputFormats(for: first, options: options).first ?? target
        }
        return rejected
    }

    func remove(_ job: Job) { jobs.removeAll { $0.id == job.id } }

    func clear() {
        guard !isConverting else { return }
        jobs.removeAll()
        lastOutputs = []
        completed = 0
    }

    func clearFinished() { jobs.removeAll { $0.isFinished } }

    // MARK: 格式

    /// 当前文件可以转换到的格式（任意一个文件支持即可选）
    var availableTargets: [Format] {
        let outs = engine.outputFormats
        guard !jobs.isEmpty else { return outs }
        return outs.filter { t in jobs.contains { j in j.format.map { engine.canConvert(from: $0, to: t, options: options) } ?? false } }
    }

    var sourceFormats: Set<Format> { Set(jobs.compactMap(\.format)) }

    /// 针对当前组合的提示语
    var fidelityNote: String? {
        let src = sourceFormats
        if src.contains(.pdf) && [.docx, .doc, .pptx, .xlsx, .odt, .rtf, .md, .html, .txt].contains(target) {
            return options.pdfReadMode == .text
                ? L.notePDFText
                : L.notePDFImages
        }
        if [.xlsx, .csv, .tsv].contains(target) && !src.isSubset(of: [.xlsx, .csv, .tsv, .json]) {
            return L.noteTablesOnly
        }
        if target == .pptx && !src.contains(.pptx) {
            return L.noteSlides
        }
        if [.pptx, .docx, .xlsx].contains(where: src.contains) && target == .pdf && !options.useLibreOffice {
            return libreOfficeAvailable
                ? L.noteOfficePDFWithLibreOffice
                : L.noteOfficePDFNoLibreOffice
        }
        return nil
    }

    var outputFolderDescription: String {
        switch outputLocation {
        case .sameAsSource: return L.savedNextToSource
        case .custom: return customFolder?.path(percentEncoded: false) ?? L.noFolderChosen
        }
    }

    var canStart: Bool {
        !isConverting && jobs.contains { !$0.isFinished } && (outputLocation == .sameAsSource || customFolder != nil)
    }

    var pendingCount: Int { jobs.filter { !$0.isFinished }.count }

    // MARK: 转换

    func start() {
        guard canStart else { return }
        let pending = jobs.filter { !$0.isFinished }
        let target = self.target
        let options = self.options
        let outDir = outputLocation == .custom ? customFolder : nil
        isConverting = true
        completed = 0
        totalToConvert = pending.count
        lastOutputs = []
        let engine = self.engine
        queue.async { [weak self] in
            for job in pending {
                DispatchQueue.main.async { job.status = .running }
                let status: Job.Status
                if let f = job.format, f == target {
                    status = .skipped(L.alreadyFormat(target.shortName))
                } else if let f = job.format, !engine.canConvert(from: f, to: target, options: options) {
                    status = .skipped(L.unsupportedTarget(target.shortName))
                } else {
                    do {
                        let outs = try autoreleasepool { try engine.convert(job.url, to: target, outputDirectory: outDir, options: options) }
                        status = .done(outs)
                    } catch {
                        status = .failed(error.localizedDescription)
                    }
                }
                DispatchQueue.main.async {
                    job.status = status
                    self?.completed += 1
                    if case .done(let outs) = status { self?.lastOutputs.append(contentsOf: outs) }
                }
            }
            DispatchQueue.main.async {
                self?.isConverting = false
                if let outs = self?.lastOutputs, !outs.isEmpty, !NSApp.isActive {
                    NSApp.requestUserAttention(.informationalRequest)
                }
            }
        }
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L.choosePrompt
        panel.message = L.chooseFolderMessage
        if panel.runModal() == .OK, let u = panel.url {
            customFolder = u
            outputLocation = .custom
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = L.add
        panel.message = L.chooseFilesMessage
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

// MARK: - 格式外观

extension Format {
    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .docx, .doc, .odt, .rtf: return "doc.text"
        case .pptx: return "play.rectangle"
        case .xlsx, .csv, .tsv: return "tablecells"
        case .md: return "number"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .txt: return "text.alignleft"
        case .json: return "curlybraces"
        case .epub: return "book"
        case .tex: return "function"
        case .png, .jpg: return "photo"
        }
    }

    var tint: Color {
        switch self {
        case .pdf: return Color(red: 0.86, green: 0.2, blue: 0.18)
        case .docx, .doc: return Color(red: 0.16, green: 0.36, blue: 0.75)
        case .pptx: return Color(red: 0.85, green: 0.38, blue: 0.16)
        case .xlsx: return Color(red: 0.1, green: 0.52, blue: 0.3)
        case .csv, .tsv: return Color(red: 0.2, green: 0.6, blue: 0.45)
        case .md: return Color(red: 0.4, green: 0.36, blue: 0.7)
        case .html: return Color(red: 0.05, green: 0.55, blue: 0.62)
        case .json: return Color(red: 0.62, green: 0.48, blue: 0.1)
        case .epub: return Color(red: 0.55, green: 0.3, blue: 0.55)
        case .png, .jpg: return Color(red: 0.75, green: 0.3, blue: 0.5)
        default: return Color.gray
        }
    }

    /// 选择目标格式时的说明
    var targetSubtitle: String { L.targetSubtitle(self) }
}
