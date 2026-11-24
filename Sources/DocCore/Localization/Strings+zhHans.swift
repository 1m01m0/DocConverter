// 简体中文
struct StringsZhHans: LocalizedStrings {
    let listSeparator = "、"
    let appName = "文档转换器"

    let dropTitle = "把文件拖到这里"
    let dropSubtitle = "PDF、Word、PowerPoint、Excel、Markdown、HTML、TXT、CSV、JSON、RTF、ODT、EPUB、图片 互相转换"
    let chooseFiles = "选择文件…"
    let dropHint = "也可以拖入整个文件夹，或把文件拖到程序坞图标上"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "不支持的文件已忽略：\(list) 等 \(total) 个文件" : "不支持的文件已忽略：\(list)"
    }

    func fileCount(_ n: Int) -> String { "\(n) 个文件" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "正在转换 \(i)/\(n)" }
    let add = "添加"
    let removeFinished = "移除已完成"
    let clear = "清空"
    let revealSource = "在 Finder 中显示源文件"
    let revealResult = "在 Finder 中显示结果"
    let openResult = "打开结果"
    let removeFromList = "从列表移除"
    let unknownFormat = "未知格式"
    let convertingStatus = "正在转换…"
    func skipped(_ reason: String) -> String { "已跳过：\(reason)" }
    let open = "打开"
    let showInFinder = "在 Finder 中显示"

    let convertTo = "转换为"
    let saveTo = "保存到"
    let chooseEllipsis = "选择…"
    let advancedOptions = "高级选项"
    func outputsDone(_ n: Int) -> String { "已完成 \(n) 个输出" }
    let convertingButton = "转换中…"
    let startConvert = "开始转换"
    func startConvertCount(_ n: Int) -> String { "开始转换（\(n)）" }
    func cannotConvertTo(_ format: String) -> String { "当前文件不能转换为 \(format)" }

    let pageLabel = "页面"
    let landscape = "横向"
    func bodyFontSize(_ pt: Int) -> String { "正文 \(pt) pt" }
    let margins = "页边距"
    let marginNarrow = "窄"
    let marginNormal = "标准"
    let marginWide = "宽"
    let readPDF = "读取 PDF"
    let ocrScannedPages = "扫描页文字识别（OCR）"
    let slideSplitLabel = "拆分幻灯片依据"
    func headingLevel(_ n: Int) -> String {
        let cn = ["一", "二", "三", "四", "五", "六"]
        return (1...6).contains(n) ? "\(cn[n - 1])级标题" : "\(n) 级标题"
    }
    let includeSpeakerNotes = "读取时包含演讲者备注"
    let imagesLabel = "图片"
    let resolution = "分辨率"
    let embedImagesInMarkdown = "Markdown 中图片内嵌（不另存 _assets 文件夹）"
    let highFidelity = "高保真"
    let useLibreOffice = "使用 LibreOffice 转换 Office → PDF（保留原版式）"
    let libreOfficeMissing = "未检测到 LibreOffice。安装后（libreoffice.org 或 brew install --cask libreoffice）即可启用。"

    let language = "语言"
    func followSystem(_ resolved: String) -> String { "跟随系统（\(resolved)）" }
    let relaunchNote = "系统菜单会在重新打开 App 后切换语言"

    let sameAsSource = "与源文件相同"
    let customFolder = "指定文件夹"
    let savedNextToSource = "保存在每个源文件旁边"
    let noFolderChosen = "未选择文件夹"
    let choosePrompt = "选择"
    let chooseFolderMessage = "选择转换结果的保存位置"
    let chooseFilesMessage = "选择要转换的文件（也可以选择文件夹）"

    let notePDFText = "PDF 转可编辑格式是提取文字与结构（标题、段落、列表、简单表格），不保留原版式。需要保持外观可在「高级选项」中选「整页转图片」。"
    let notePDFImages = "当前为「整页转图片」模式：外观与原 PDF 一致，但文字不可编辑。"
    let noteTablesOnly = "导出为表格时只保留文档中的表格；没有表格的文档会把文字逐行写入。"
    let noteSlides = "按标题自动拆分幻灯片（可在「高级选项」中调整拆分级别），过长的内容会自动分页。"
    let noteOfficePDFWithLibreOffice = "内置引擎按内容重新排版。需要完全保留 Office 原版式，可在「高级选项」中启用 LibreOffice。"
    let noteOfficePDFNoLibreOffice = "内置引擎按内容重新排版，不保留 Office 文件的原始版式（安装 LibreOffice 后可启用高保真模式）。"

    func alreadyFormat(_ format: String) -> String { "已经是 \(format) 格式" }
    func unsupportedTarget(_ format: String) -> String { "不支持转换为 \(format)" }

    let addFilesMenu = "添加文件…"
    let convertMenu = "转换"
    let startConvertMenu = "开始转换"
    let chooseSaveLocationMenu = "选择保存位置…"
    let clearListMenu = "清空列表"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "便携文档"
        case .docx: return "Word 文档"
        case .doc: return "Word 97-2003"
        case .pptx: return "演示文稿"
        case .xlsx: return "表格"
        case .md: return "轻量标记"
        case .html: return "网页"
        case .txt: return "纯文本"
        case .csv: return "逗号分隔"
        case .tsv: return "制表符分隔"
        case .json: return "结构化数据"
        case .rtf: return "富文本"
        case .odt: return "开放文档格式"
        case .epub: return "电子书"
        case .tex: return "LaTeX 源码"
        case .png, .jpg: return "每页一张图"
        }
    }
    let plainText = "纯文本"
    let epubBook = "EPUB 电子书"
    let pngImage = "PNG 图片"
    let jpegImage = "JPEG 图片"
    let pdfModeText = "提取文字（可编辑）"
    let pdfModeImages = "整页转图片（保留版式）"

    func errUnsupportedInput(_ s: String) -> String { "不支持读取该格式：\(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "不支持输出该格式：\(s)" }
    func errInvalidFile(_ s: String) -> String { "文件无效或已损坏：\(s)" }
    let errEmptyDocument = "文档中没有可转换的内容"
    func errFailed(_ s: String) -> String { "转换失败：\(s)" }
    let noExtension = "（无扩展名）"
    let pdfContextFailed = "无法创建 PDF 上下文"
    let pdfLayoutFailed = "PDF 排版失败"
    let cannotOpenPDF = "无法打开 PDF"
    let pdfEncrypted = "PDF 已加密，需要密码"
    func systemCannotParse(_ format: String) -> String { "系统无法解析该 \(format) 文件" }
    let libreOfficeNotFound = "未找到 LibreOffice"
    let libreOfficeTimeout = "LibreOffice 转换超时"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice 未生成输出文件（退出码 \(code)）" }
    let notZip = "不是有效的 ZIP 容器"
    let zipDirectoryMissing = "找不到 ZIP 目录"
    func missingPart(_ name: String) -> String { "缺少 \(name)" }
    let epubNoPackage = "缺少 EPUB 目录信息"
    let invalidJSON = "JSON 格式错误"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[图片]" : "[图片: \(alt)]" }
    func pageN(_ n: Int) -> String { "第 \(n) 页" }
    func slideN(_ n: Int) -> String { "幻灯片 \(n)" }
    func partN(_ n: Int) -> String { "第 \(n) 部分" }
    func tableN(_ n: Int) -> String { "表\(n)" }
    func columnN(_ n: Int) -> String { "列\(n)" }
    let speakerNotes = "演讲者备注"
    let chartPlaceholder = "[图表]"
    let continuedSuffix = "（续）"
    let untitledDocument = "文档"
    let untitledPresentation = "演示文稿"
    let sheetContent = "内容"
    let placeholderTitle = "标题"
    let placeholderSubtitle = "副标题"
    let placeholderBody = "正文"
    let pdfRasterizer = "PDF 栅格化"

    let cliUsage = "用法: docconv -t <目标格式> [选项] <文件...>"
    let cliOptions = "选项:"
    let cliTo = "目标格式（必填）"
    let cliOut = "输出目录（默认：与源文件相同）"
    let cliPage = "页面大小（PDF/Word）"
    let cliLandscape = "横向"
    let cliFontSize = "正文字号（默认 11）"
    let cliMargin = "页边距（默认 56）"
    let cliPdfMode = "读取 PDF：提取文字 / 整页转图片"
    let cliNoOCR = "不对扫描页做文字识别"
    let cliSplit = "生成 PPT 时按几级标题拆分幻灯片（默认 2）"
    let cliNotes = "读取 PPT 时包含演讲者备注"
    let cliEmbedImages = "Markdown 中图片以 data URI 内嵌"
    let cliDPI = "图片输出分辨率（默认 150）"
    let cliLibreOffice = "已安装 LibreOffice 时使用其高保真转换 Office → PDF"
    let cliLang = "界面语言：zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "打印中间表示（调试）"
    let cliVerbose = "显示系统框架的调试日志"
    let cliFormats = "列出支持的格式"
    let cliHelp = "显示本帮助"
    let cliReadable = "可读取"
    let cliWritable = "可输出"
    let cliReadMark = "读"
    let cliWriteMark = "写"
    func cliUnknownFormat(_ s: String) -> String { "未知格式: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "未知语言: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "未知选项: \(s)" }

    let usageFolders = "读取你选择的文件，并把转换结果保存在源文件旁边。"
    let usageRemovable = "读取和保存移动磁盘上的文件。"
    let usageNetwork = "读取和保存网络磁盘上的文件。"
}
