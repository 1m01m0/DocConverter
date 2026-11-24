import Foundation

// 界面语言。所有面向用户的文字都通过 `L.xxx` 取得；每种语言是一个实现 `LocalizedStrings` 的结构体，
// 漏翻任何一条都会编译失败。带参数的文字写成函数，方便各语言调整语序和单复数。

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case fr
    case de
    case es

    public var id: String { rawValue }

    /// 用该语言自己的文字写出的名称
    public var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    public var strings: LocalizedStrings {
        switch self {
        case .zhHans: return StringTables.zhHans
        case .zhHant: return StringTables.zhHant
        case .en: return StringTables.en
        case .ja: return StringTables.ja
        case .ko: return StringTables.ko
        case .fr: return StringTables.fr
        case .de: return StringTables.de
        case .es: return StringTables.es
        }
    }

    /// 把 "zh_CN.UTF-8"、"zh-Hant-TW"、"en-US"、"pt-BR" 之类的标识匹配到支持的语言
    public static func match(_ identifier: String) -> AppLanguage? {
        var s = identifier.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "_", with: "-")
        if let dot = s.firstIndex(where: { $0 == "." || $0 == "@" }) { s = String(s[..<dot]) }
        if s.isEmpty || s == "c" || s == "posix" { return nil }
        let parts = s.split(separator: "-").map(String.init)
        guard let lang = parts.first else { return nil }
        if lang == "zh" {
            let traditional = parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo")
            return traditional ? .zhHant : .zhHans
        }
        return AppLanguage.allCases.first { $0.rawValue == lang }
    }

    /// 按偏好顺序挑第一个支持的语言；都不支持时用英文
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        for id in identifiers { if let l = match(id) { return l } }
        return .en
    }

    /// 系统语言（命令行优先看 LC_ALL / LC_MESSAGES / LANG）
    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> AppLanguage {
        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let v = env[key], let l = match(v) { return l }
        }
        return preferred(from: Locale.preferredLanguages)
    }
}

public enum Localizer {
    private static let lock = NSLock()
    private static var _current = AppLanguage.preferred(from: Locale.preferredLanguages)

    /// 当前语言；转换在后台线程进行，所以加锁
    public static var current: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); _current = newValue; lock.unlock() }
    }
}

/// 当前语言的文字表
public var L: LocalizedStrings { Localizer.current.strings }

enum StringTables {
    static let zhHans: LocalizedStrings = StringsZhHans()
    static let zhHant: LocalizedStrings = StringsZhHant()
    static let en: LocalizedStrings = StringsEn()
    static let ja: LocalizedStrings = StringsJa()
    static let ko: LocalizedStrings = StringsKo()
    static let fr: LocalizedStrings = StringsFr()
    static let de: LocalizedStrings = StringsDe()
    static let es: LocalizedStrings = StringsEs()
}

public extension LocalizedStrings {
    /// 用本语言的分隔符连接
    func list(_ items: [String]) -> String { items.joined(separator: listSeparator) }
}

public protocol LocalizedStrings {
    // MARK: 通用
    var listSeparator: String { get }
    var appName: String { get }

    // MARK: 拖放区
    var dropTitle: String { get }
    var dropSubtitle: String { get }
    var chooseFiles: String { get }
    var dropHint: String { get }
    /// list：前几个文件名（已用 listSeparator 连接）；shown：list 里有几个；total：一共几个
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String

    // MARK: 文件列表
    func fileCount(_ n: Int) -> String
    func convertingProgress(_ i: Int, _ n: Int) -> String
    var add: String { get }
    var removeFinished: String { get }
    var clear: String { get }
    var revealSource: String { get }
    var revealResult: String { get }
    var openResult: String { get }
    var removeFromList: String { get }
    var unknownFormat: String { get }
    var convertingStatus: String { get }
    func skipped(_ reason: String) -> String
    var open: String { get }
    var showInFinder: String { get }

    // MARK: 设置面板
    var convertTo: String { get }
    var saveTo: String { get }
    var chooseEllipsis: String { get }
    var advancedOptions: String { get }
    func outputsDone(_ n: Int) -> String
    var convertingButton: String { get }
    var startConvert: String { get }
    func startConvertCount(_ n: Int) -> String
    func cannotConvertTo(_ format: String) -> String

    // MARK: 高级选项
    var pageLabel: String { get }
    var landscape: String { get }
    func bodyFontSize(_ pt: Int) -> String
    var margins: String { get }
    var marginNarrow: String { get }
    var marginNormal: String { get }
    var marginWide: String { get }
    var readPDF: String { get }
    var ocrScannedPages: String { get }
    var slideSplitLabel: String { get }
    func headingLevel(_ n: Int) -> String
    var includeSpeakerNotes: String { get }
    var imagesLabel: String { get }
    var resolution: String { get }
    var embedImagesInMarkdown: String { get }
    var highFidelity: String { get }
    var useLibreOffice: String { get }
    var libreOfficeMissing: String { get }

    // MARK: 语言
    var language: String { get }
    func followSystem(_ resolved: String) -> String
    var relaunchNote: String { get }

    // MARK: 保存位置
    var sameAsSource: String { get }
    var customFolder: String { get }
    var savedNextToSource: String { get }
    var noFolderChosen: String { get }
    var choosePrompt: String { get }
    var chooseFolderMessage: String { get }
    var chooseFilesMessage: String { get }

    // MARK: 提示
    var notePDFText: String { get }
    var notePDFImages: String { get }
    var noteTablesOnly: String { get }
    var noteSlides: String { get }
    var noteOfficePDFWithLibreOffice: String { get }
    var noteOfficePDFNoLibreOffice: String { get }

    // MARK: 跳过原因
    func alreadyFormat(_ format: String) -> String
    func unsupportedTarget(_ format: String) -> String

    // MARK: 菜单
    var addFilesMenu: String { get }
    var convertMenu: String { get }
    var startConvertMenu: String { get }
    var chooseSaveLocationMenu: String { get }
    var clearListMenu: String { get }

    // MARK: 格式
    func targetSubtitle(_ format: Format) -> String
    var plainText: String { get }
    var epubBook: String { get }
    var pngImage: String { get }
    var jpegImage: String { get }
    var pdfModeText: String { get }
    var pdfModeImages: String { get }

    // MARK: 错误
    func errUnsupportedInput(_ s: String) -> String
    func errUnsupportedOutput(_ s: String) -> String
    func errInvalidFile(_ s: String) -> String
    var errEmptyDocument: String { get }
    func errFailed(_ s: String) -> String
    var noExtension: String { get }
    var pdfContextFailed: String { get }
    var pdfLayoutFailed: String { get }
    var cannotOpenPDF: String { get }
    var pdfEncrypted: String { get }
    func systemCannotParse(_ format: String) -> String
    var libreOfficeNotFound: String { get }
    var libreOfficeTimeout: String { get }
    func libreOfficeNoOutput(_ code: Int32) -> String
    var notZip: String { get }
    var zipDirectoryMissing: String { get }
    func missingPart(_ name: String) -> String
    var epubNoPackage: String { get }
    var invalidJSON: String { get }

    // MARK: 写进生成文档里的文字
    func imagePlaceholder(_ alt: String) -> String
    func pageN(_ n: Int) -> String
    func slideN(_ n: Int) -> String
    func partN(_ n: Int) -> String
    func tableN(_ n: Int) -> String
    func columnN(_ n: Int) -> String
    var speakerNotes: String { get }
    var chartPlaceholder: String { get }
    var continuedSuffix: String { get }
    var untitledDocument: String { get }
    var untitledPresentation: String { get }
    var sheetContent: String { get }
    var placeholderTitle: String { get }
    var placeholderSubtitle: String { get }
    var placeholderBody: String { get }
    var pdfRasterizer: String { get }

    // MARK: 命令行
    var cliUsage: String { get }
    var cliOptions: String { get }
    var cliTo: String { get }
    var cliOut: String { get }
    var cliPage: String { get }
    var cliLandscape: String { get }
    var cliFontSize: String { get }
    var cliMargin: String { get }
    var cliPdfMode: String { get }
    var cliNoOCR: String { get }
    var cliSplit: String { get }
    var cliNotes: String { get }
    var cliEmbedImages: String { get }
    var cliDPI: String { get }
    var cliLibreOffice: String { get }
    var cliLang: String { get }
    var cliDump: String { get }
    var cliVerbose: String { get }
    var cliFormats: String { get }
    var cliHelp: String { get }
    var cliReadable: String { get }
    var cliWritable: String { get }
    var cliReadMark: String { get }
    var cliWriteMark: String { get }
    func cliUnknownFormat(_ s: String) -> String
    func cliUnknownLanguage(_ s: String) -> String
    func cliUnknownOption(_ s: String) -> String

    // MARK: Info.plist（系统权限提示）
    var usageFolders: String { get }
    var usageRemovable: String { get }
    var usageNetwork: String { get }
}
