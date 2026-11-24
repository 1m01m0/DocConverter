// 日本語
struct StringsJa: LocalizedStrings {
    let listSeparator = "、"
    let appName = "ドキュメント変換"

    let dropTitle = "ここにファイルをドロップ"
    let dropSubtitle = "PDF、Word、PowerPoint、Excel、Markdown、HTML、TXT、CSV、JSON、RTF、ODT、EPUB、画像を相互に変換"
    let chooseFiles = "ファイルを選択…"
    let dropHint = "フォルダごとドロップしたり、Dock のアイコンにファイルをドロップしたりすることもできます"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "未対応のファイルを無視しました：\(list) ほか（計 \(total) 件）" : "未対応のファイルを無視しました：\(list)"
    }

    func fileCount(_ n: Int) -> String { "\(n) 個のファイル" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "変換中 \(i)/\(n)" }
    let add = "追加"
    let removeFinished = "完了分を削除"
    let clear = "すべて消去"
    let revealSource = "元のファイルを Finder に表示"
    let revealResult = "変換結果を Finder に表示"
    let openResult = "変換結果を開く"
    let removeFromList = "リストから削除"
    let unknownFormat = "不明な形式"
    let convertingStatus = "変換中…"
    func skipped(_ reason: String) -> String { "スキップ：\(reason)" }
    let open = "開く"
    let showInFinder = "Finder に表示"

    let convertTo = "変換先"
    let saveTo = "保存先"
    let chooseEllipsis = "選択…"
    let advancedOptions = "詳細オプション"
    func outputsDone(_ n: Int) -> String { "\(n) 個のファイルを作成しました" }
    let convertingButton = "変換中…"
    let startConvert = "変換開始"
    func startConvertCount(_ n: Int) -> String { "変換開始（\(n)）" }
    func cannotConvertTo(_ format: String) -> String { "現在のファイルは \(format) に変換できません" }

    let pageLabel = "ページ"
    let landscape = "横向き"
    func bodyFontSize(_ pt: Int) -> String { "本文 \(pt) pt" }
    let margins = "余白"
    let marginNarrow = "狭い"
    let marginNormal = "標準"
    let marginWide = "広い"
    let readPDF = "PDF の読み込み"
    let ocrScannedPages = "スキャンページの文字認識（OCR）"
    let slideSplitLabel = "スライドの区切り"
    func headingLevel(_ n: Int) -> String { "見出し \(n)" }
    let includeSpeakerNotes = "読み込み時に発表者ノートを含める"
    let imagesLabel = "画像"
    let resolution = "解像度"
    let embedImagesInMarkdown = "Markdown に画像を埋め込む（_assets フォルダを作らない）"
    let highFidelity = "高忠実度"
    let useLibreOffice = "LibreOffice で Office → PDF を変換（元のレイアウトを保持）"
    let libreOfficeMissing = "LibreOffice が見つかりません。インストールすると（libreoffice.org または brew install --cask libreoffice）使用できます。"

    let language = "言語"
    func followSystem(_ resolved: String) -> String { "システムに従う（\(resolved)）" }
    let relaunchNote = "システムのメニューはアプリを開き直すと切り替わります"

    let sameAsSource = "元のファイルと同じ場所"
    let customFolder = "フォルダを指定"
    let savedNextToSource = "各ファイルと同じ場所に保存"
    let noFolderChosen = "フォルダが選択されていません"
    let choosePrompt = "選択"
    let chooseFolderMessage = "変換結果の保存先を選択してください"
    let chooseFilesMessage = "変換するファイルを選択してください（フォルダも選択できます）"

    let notePDFText = "PDF を編集可能な形式に変換すると、文字と構造（見出し、段落、リスト、簡単な表）を抽出します。元のレイアウトは保持されません。見た目を保つには「詳細オプション」で「ページ全体を画像に」を選んでください。"
    let notePDFImages = "「ページ全体を画像に」モード：見た目は元の PDF と同じですが、文字は編集できません。"
    let noteTablesOnly = "表計算形式に書き出すと、文書内の表だけが残ります。表のない文書は文字を 1 行ずつ書き込みます。"
    let noteSlides = "見出しごとにスライドを自動で区切ります（「詳細オプション」で変更可）。長い内容は次のスライドに続きます。"
    let noteOfficePDFWithLibreOffice = "内蔵エンジンは内容をレイアウトし直します。Office の元のレイアウトを完全に保つには「詳細オプション」で LibreOffice を有効にしてください。"
    let noteOfficePDFNoLibreOffice = "内蔵エンジンは内容をレイアウトし直すため、Office ファイルの元のレイアウトは保持されません（LibreOffice をインストールすると高忠実度モードを使用できます）。"

    func alreadyFormat(_ format: String) -> String { "すでに \(format) 形式です" }
    func unsupportedTarget(_ format: String) -> String { "\(format) には変換できません" }

    let addFilesMenu = "ファイルを追加…"
    let convertMenu = "変換"
    let startConvertMenu = "変換開始"
    let chooseSaveLocationMenu = "保存先を選択…"
    let clearListMenu = "リストを消去"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "ポータブル文書"
        case .docx: return "Word 文書"
        case .doc: return "Word 97-2003"
        case .pptx: return "プレゼンテーション"
        case .xlsx: return "表計算"
        case .md: return "軽量マークアップ"
        case .html: return "Web ページ"
        case .txt: return "プレーンテキスト"
        case .csv: return "カンマ区切り"
        case .tsv: return "タブ区切り"
        case .json: return "構造化データ"
        case .rtf: return "リッチテキスト"
        case .odt: return "OpenDocument"
        case .epub: return "電子書籍"
        case .tex: return "LaTeX ソース"
        case .png, .jpg: return "1 ページ 1 画像"
        }
    }
    let plainText = "プレーンテキスト"
    let epubBook = "EPUB 電子書籍"
    let pngImage = "PNG 画像"
    let jpegImage = "JPEG 画像"
    let pdfModeText = "テキストを抽出（編集可能）"
    let pdfModeImages = "ページ全体を画像に（レイアウト保持）"

    func errUnsupportedInput(_ s: String) -> String { "この形式は読み込めません：\(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "この形式には書き出せません：\(s)" }
    func errInvalidFile(_ s: String) -> String { "ファイルが無効か破損しています：\(s)" }
    let errEmptyDocument = "変換できる内容がありません"
    func errFailed(_ s: String) -> String { "変換に失敗しました：\(s)" }
    let noExtension = "（拡張子なし）"
    let pdfContextFailed = "PDF コンテキストを作成できません"
    let pdfLayoutFailed = "PDF のレイアウトに失敗しました"
    let cannotOpenPDF = "PDF を開けません"
    let pdfEncrypted = "PDF が暗号化されているため、パスワードが必要です"
    func systemCannotParse(_ format: String) -> String { "システムがこの \(format) ファイルを解析できません" }
    let libreOfficeNotFound = "LibreOffice が見つかりません"
    let libreOfficeTimeout = "LibreOffice の変換がタイムアウトしました"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice が出力ファイルを作成しませんでした（終了コード \(code)）" }
    let notZip = "有効な ZIP コンテナではありません"
    let zipDirectoryMissing = "ZIP のディレクトリが見つかりません"
    func missingPart(_ name: String) -> String { "\(name) がありません" }
    let epubNoPackage = "EPUB のパッケージ情報がありません"
    let invalidJSON = "JSON の形式が正しくありません"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[画像]" : "[画像: \(alt)]" }
    func pageN(_ n: Int) -> String { "\(n) ページ" }
    func slideN(_ n: Int) -> String { "スライド \(n)" }
    func partN(_ n: Int) -> String { "パート \(n)" }
    func tableN(_ n: Int) -> String { "表\(n)" }
    func columnN(_ n: Int) -> String { "列\(n)" }
    let speakerNotes = "発表者ノート"
    let chartPlaceholder = "[グラフ]"
    let continuedSuffix = "（続き）"
    let untitledDocument = "ドキュメント"
    let untitledPresentation = "プレゼンテーション"
    let sheetContent = "内容"
    let placeholderTitle = "タイトル"
    let placeholderSubtitle = "サブタイトル"
    let placeholderBody = "本文"
    let pdfRasterizer = "PDF ラスタライズ"

    let cliUsage = "使い方: docconv -t <変換先形式> [オプション] <ファイル...>"
    let cliOptions = "オプション:"
    let cliTo = "変換先の形式（必須）"
    let cliOut = "出力フォルダ（既定：元のファイルと同じ場所）"
    let cliPage = "用紙サイズ（PDF/Word）"
    let cliLandscape = "横向き"
    let cliFontSize = "本文の文字サイズ（既定 11）"
    let cliMargin = "余白（既定 56）"
    let cliPdfMode = "PDF の読み込み：テキスト抽出 / ページ全体を画像に"
    let cliNoOCR = "スキャンページの文字認識を行わない"
    let cliSplit = "スライドを区切る見出しレベル（既定 2）"
    let cliNotes = "PowerPoint 読み込み時に発表者ノートを含める"
    let cliEmbedImages = "Markdown の画像を data URI で埋め込む"
    let cliDPI = "画像出力の解像度（既定 150）"
    let cliLibreOffice = "LibreOffice がインストールされていれば、Office → PDF を高忠実度で変換"
    let cliLang = "表示言語：zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "中間表現を表示（デバッグ用）"
    let cliVerbose = "システムフレームワークのデバッグログを表示"
    let cliFormats = "対応形式を一覧表示"
    let cliHelp = "このヘルプを表示"
    let cliReadable = "読み込み"
    let cliWritable = "書き出し"
    let cliReadMark = "読"
    let cliWriteMark = "書"
    func cliUnknownFormat(_ s: String) -> String { "不明な形式: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "不明な言語: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "不明なオプション: \(s)" }

    let usageFolders = "選択したファイルを読み込み、変換結果を元のファイルと同じ場所に保存します。"
    let usageRemovable = "リムーバブルディスク上のファイルを読み込み、保存します。"
    let usageNetwork = "ネットワークディスク上のファイルを読み込み、保存します。"
}
