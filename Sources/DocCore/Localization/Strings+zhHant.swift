// 繁體中文
struct StringsZhHant: LocalizedStrings {
    let listSeparator = "、"
    let appName = "文件轉換器"

    let dropTitle = "把檔案拖到這裡"
    let dropSubtitle = "PDF、Word、PowerPoint、Excel、Markdown、HTML、TXT、CSV、JSON、RTF、ODT、EPUB、圖片 互相轉換"
    let chooseFiles = "選擇檔案…"
    let dropHint = "也可以拖入整個資料夾，或把檔案拖到 Dock 圖示上"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "已略過不支援的檔案：\(list) 等 \(total) 個檔案" : "已略過不支援的檔案：\(list)"
    }

    func fileCount(_ n: Int) -> String { "\(n) 個檔案" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "正在轉換 \(i)/\(n)" }
    let add = "加入"
    let removeFinished = "移除已完成"
    let clear = "清除"
    let revealSource = "在 Finder 中顯示原始檔"
    let revealResult = "在 Finder 中顯示結果"
    let openResult = "開啟結果"
    let removeFromList = "從列表移除"
    let unknownFormat = "未知格式"
    let convertingStatus = "正在轉換…"
    func skipped(_ reason: String) -> String { "已略過：\(reason)" }
    let open = "開啟"
    let showInFinder = "在 Finder 中顯示"

    let convertTo = "轉換為"
    let saveTo = "儲存到"
    let chooseEllipsis = "選擇…"
    let advancedOptions = "進階選項"
    func outputsDone(_ n: Int) -> String { "已完成 \(n) 個輸出" }
    let convertingButton = "轉換中…"
    let startConvert = "開始轉換"
    func startConvertCount(_ n: Int) -> String { "開始轉換（\(n)）" }
    func cannotConvertTo(_ format: String) -> String { "目前的檔案無法轉換為 \(format)" }

    let pageLabel = "頁面"
    let landscape = "橫向"
    func bodyFontSize(_ pt: Int) -> String { "內文 \(pt) pt" }
    let margins = "邊界"
    let marginNarrow = "窄"
    let marginNormal = "標準"
    let marginWide = "寬"
    let readPDF = "讀取 PDF"
    let ocrScannedPages = "掃描頁文字辨識（OCR）"
    let slideSplitLabel = "分割投影片依據"
    func headingLevel(_ n: Int) -> String {
        let cn = ["一", "二", "三", "四", "五", "六"]
        return (1...6).contains(n) ? "\(cn[n - 1])級標題" : "\(n) 級標題"
    }
    let includeSpeakerNotes = "讀取時包含備忘稿"
    let imagesLabel = "圖片"
    let resolution = "解析度"
    let embedImagesInMarkdown = "Markdown 中內嵌圖片（不另存 _assets 資料夾）"
    let highFidelity = "高保真"
    let useLibreOffice = "使用 LibreOffice 轉換 Office → PDF（保留原始版面）"
    let libreOfficeMissing = "未偵測到 LibreOffice。安裝後（libreoffice.org 或 brew install --cask libreoffice）即可啟用。"

    let language = "語言"
    func followSystem(_ resolved: String) -> String { "跟隨系統（\(resolved)）" }
    let relaunchNote = "系統選單會在重新開啟 App 後切換語言"

    let sameAsSource = "與原始檔相同"
    let customFolder = "指定資料夾"
    let savedNextToSource = "儲存在每個原始檔旁邊"
    let noFolderChosen = "未選擇資料夾"
    let choosePrompt = "選擇"
    let chooseFolderMessage = "選擇轉換結果的儲存位置"
    let chooseFilesMessage = "選擇要轉換的檔案（也可以選擇資料夾）"

    let notePDFText = "PDF 轉成可編輯格式是擷取文字與結構（標題、段落、清單、簡單表格），不保留原始版面。需要保持外觀可在「進階選項」中選「整頁轉圖片」。"
    let notePDFImages = "目前為「整頁轉圖片」模式：外觀與原 PDF 一致，但文字無法編輯。"
    let noteTablesOnly = "匯出為試算表時只保留文件中的表格；沒有表格的文件會把文字逐行寫入。"
    let noteSlides = "依標題自動分割投影片（可在「進階選項」中調整分割層級），過長的內容會自動分頁。"
    let noteOfficePDFWithLibreOffice = "內建引擎會依內容重新排版。需要完整保留 Office 原始版面，可在「進階選項」中啟用 LibreOffice。"
    let noteOfficePDFNoLibreOffice = "內建引擎會依內容重新排版，不保留 Office 檔案的原始版面（安裝 LibreOffice 後可啟用高保真模式）。"

    func alreadyFormat(_ format: String) -> String { "已經是 \(format) 格式" }
    func unsupportedTarget(_ format: String) -> String { "不支援轉換為 \(format)" }

    let addFilesMenu = "加入檔案…"
    let convertMenu = "轉換"
    let startConvertMenu = "開始轉換"
    let chooseSaveLocationMenu = "選擇儲存位置…"
    let clearListMenu = "清除列表"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "可攜式文件"
        case .docx: return "Word 文件"
        case .doc: return "Word 97-2003"
        case .pptx: return "簡報"
        case .xlsx: return "試算表"
        case .md: return "輕量標記"
        case .html: return "網頁"
        case .txt: return "純文字"
        case .csv: return "逗號分隔"
        case .tsv: return "定位字元分隔"
        case .json: return "結構化資料"
        case .rtf: return "RTF 文字"
        case .odt: return "開放文件格式"
        case .epub: return "電子書"
        case .tex: return "LaTeX 原始碼"
        case .png, .jpg: return "每頁一張圖"
        }
    }
    let plainText = "純文字"
    let epubBook = "EPUB 電子書"
    let pngImage = "PNG 圖片"
    let jpegImage = "JPEG 圖片"
    let pdfModeText = "擷取文字（可編輯）"
    let pdfModeImages = "整頁轉圖片（保留版面）"

    func errUnsupportedInput(_ s: String) -> String { "不支援讀取此格式：\(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "不支援輸出此格式：\(s)" }
    func errInvalidFile(_ s: String) -> String { "檔案無效或已損毀：\(s)" }
    let errEmptyDocument = "文件中沒有可轉換的內容"
    func errFailed(_ s: String) -> String { "轉換失敗：\(s)" }
    let noExtension = "（無副檔名）"
    let pdfContextFailed = "無法建立 PDF 繪圖環境"
    let pdfLayoutFailed = "PDF 排版失敗"
    let cannotOpenPDF = "無法開啟 PDF"
    let pdfEncrypted = "PDF 已加密，需要密碼"
    func systemCannotParse(_ format: String) -> String { "系統無法解析此 \(format) 檔案" }
    let libreOfficeNotFound = "找不到 LibreOffice"
    let libreOfficeTimeout = "LibreOffice 轉換逾時"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice 沒有產生輸出檔案（結束代碼 \(code)）" }
    let notZip = "不是有效的 ZIP 容器"
    let zipDirectoryMissing = "找不到 ZIP 目錄"
    func missingPart(_ name: String) -> String { "缺少 \(name)" }
    let epubNoPackage = "缺少 EPUB 目錄資訊"
    let invalidJSON = "JSON 格式錯誤"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[圖片]" : "[圖片: \(alt)]" }
    func pageN(_ n: Int) -> String { "第 \(n) 頁" }
    func slideN(_ n: Int) -> String { "投影片 \(n)" }
    func partN(_ n: Int) -> String { "第 \(n) 部分" }
    func tableN(_ n: Int) -> String { "表\(n)" }
    func columnN(_ n: Int) -> String { "欄\(n)" }
    let speakerNotes = "備忘稿"
    let chartPlaceholder = "[圖表]"
    let continuedSuffix = "（續）"
    let untitledDocument = "文件"
    let untitledPresentation = "簡報"
    let sheetContent = "內容"
    let placeholderTitle = "標題"
    let placeholderSubtitle = "副標題"
    let placeholderBody = "內文"
    let pdfRasterizer = "PDF 點陣化"

    let cliUsage = "用法: docconv -t <目標格式> [選項] <檔案...>"
    let cliOptions = "選項:"
    let cliTo = "目標格式（必填）"
    let cliOut = "輸出資料夾（預設：與原始檔相同）"
    let cliPage = "頁面大小（PDF/Word）"
    let cliLandscape = "橫向"
    let cliFontSize = "內文字級（預設 11）"
    let cliMargin = "邊界（預設 56）"
    let cliPdfMode = "讀取 PDF：擷取文字 / 整頁轉圖片"
    let cliNoOCR = "不對掃描頁進行文字辨識"
    let cliSplit = "產生簡報時依第幾級標題分割投影片（預設 2）"
    let cliNotes = "讀取簡報時包含備忘稿"
    let cliEmbedImages = "Markdown 中的圖片以 data URI 內嵌"
    let cliDPI = "圖片輸出解析度（預設 150）"
    let cliLibreOffice = "已安裝 LibreOffice 時，用它高保真轉換 Office → PDF"
    let cliLang = "介面語言：zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "列印中間表示（除錯用）"
    let cliVerbose = "顯示系統框架的除錯記錄"
    let cliFormats = "列出支援的格式"
    let cliHelp = "顯示本說明"
    let cliReadable = "可讀取"
    let cliWritable = "可輸出"
    let cliReadMark = "讀"
    let cliWriteMark = "寫"
    func cliUnknownFormat(_ s: String) -> String { "未知格式: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "未知語言: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "未知選項: \(s)" }

    let usageFolders = "讀取你選擇的檔案，並把轉換結果儲存在原始檔旁邊。"
    let usageRemovable = "讀取和儲存外接磁碟上的檔案。"
    let usageNetwork = "讀取和儲存網路磁碟上的檔案。"
}
