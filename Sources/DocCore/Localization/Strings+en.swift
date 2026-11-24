// English
struct StringsEn: LocalizedStrings {
    let listSeparator = ", "
    let appName = "Doc Converter"

    let dropTitle = "Drop Files Here"
    let dropSubtitle = "Convert between PDF, Word, PowerPoint, Excel, Markdown, HTML, TXT, CSV, JSON, RTF, ODT, EPUB and images"
    let chooseFiles = "Choose Files…"
    let dropHint = "You can also drop a whole folder, or drop files onto the Dock icon"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "Unsupported files ignored: \(list) and \(total - shown) more" : "Unsupported files ignored: \(list)"
    }

    func fileCount(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "Converting \(i) of \(n)" }
    let add = "Add"
    let removeFinished = "Remove Finished"
    let clear = "Clear"
    let revealSource = "Show Original in Finder"
    let revealResult = "Show Result in Finder"
    let openResult = "Open Result"
    let removeFromList = "Remove from List"
    let unknownFormat = "Unknown format"
    let convertingStatus = "Converting…"
    func skipped(_ reason: String) -> String { "Skipped: \(reason)" }
    let open = "Open"
    let showInFinder = "Show in Finder"

    let convertTo = "Convert to"
    let saveTo = "Save to"
    let chooseEllipsis = "Choose…"
    let advancedOptions = "Advanced Options"
    func outputsDone(_ n: Int) -> String { n == 1 ? "1 file created" : "\(n) files created" }
    let convertingButton = "Converting…"
    let startConvert = "Convert"
    func startConvertCount(_ n: Int) -> String { "Convert (\(n))" }
    func cannotConvertTo(_ format: String) -> String { "The current files can’t be converted to \(format)" }

    let pageLabel = "Page"
    let landscape = "Landscape"
    func bodyFontSize(_ pt: Int) -> String { "Body \(pt) pt" }
    let margins = "Margins"
    let marginNarrow = "Narrow"
    let marginNormal = "Normal"
    let marginWide = "Wide"
    let readPDF = "Reading PDF"
    let ocrScannedPages = "Recognize text in scanned pages (OCR)"
    let slideSplitLabel = "New slide at"
    func headingLevel(_ n: Int) -> String { "Heading \(n)" }
    let includeSpeakerNotes = "Include speaker notes when reading"
    let imagesLabel = "Images"
    let resolution = "Resolution"
    let embedImagesInMarkdown = "Embed images in Markdown (no _assets folder)"
    let highFidelity = "High fidelity"
    let useLibreOffice = "Use LibreOffice for Office → PDF (keeps the original layout)"
    let libreOfficeMissing = "LibreOffice was not found. Install it (libreoffice.org or brew install --cask libreoffice) to enable this option."

    let language = "Language"
    func followSystem(_ resolved: String) -> String { "System Default (\(resolved))" }
    let relaunchNote = "System menus switch language after the app is reopened"

    let sameAsSource = "Next to Original"
    let customFolder = "Custom Folder"
    let savedNextToSource = "Saved next to each original file"
    let noFolderChosen = "No folder chosen"
    let choosePrompt = "Choose"
    let chooseFolderMessage = "Choose where to save the converted files"
    let chooseFilesMessage = "Choose files to convert (folders work too)"

    let notePDFText = "Converting a PDF to an editable format extracts its text and structure (headings, paragraphs, lists, simple tables); the original layout is not kept. To keep the look, choose “Whole pages as images” in Advanced Options."
    let notePDFImages = "“Whole pages as images” mode: the result looks exactly like the PDF, but the text can’t be edited."
    let noteTablesOnly = "Exporting to a spreadsheet keeps only the tables; documents without tables are written line by line."
    let noteSlides = "Slides are split at headings (adjustable in Advanced Options); long content continues on extra slides."
    let noteOfficePDFWithLibreOffice = "The built-in engine lays out the content again. To keep the exact Office layout, enable LibreOffice in Advanced Options."
    let noteOfficePDFNoLibreOffice = "The built-in engine lays out the content again and doesn’t keep the original Office layout (install LibreOffice to enable high-fidelity mode)."

    func alreadyFormat(_ format: String) -> String { "already in \(format) format" }
    func unsupportedTarget(_ format: String) -> String { "can’t be converted to \(format)" }

    let addFilesMenu = "Add Files…"
    let convertMenu = "Convert"
    let startConvertMenu = "Start Conversion"
    let chooseSaveLocationMenu = "Choose Save Location…"
    let clearListMenu = "Clear List"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "Portable document"
        case .docx: return "Word document"
        case .doc: return "Word 97–2003"
        case .pptx: return "Presentation"
        case .xlsx: return "Spreadsheet"
        case .md: return "Lightweight markup"
        case .html: return "Web page"
        case .txt: return "Plain text"
        case .csv: return "Comma-separated"
        case .tsv: return "Tab-separated"
        case .json: return "Structured data"
        case .rtf: return "Rich text"
        case .odt: return "OpenDocument"
        case .epub: return "E-book"
        case .tex: return "LaTeX source"
        case .png, .jpg: return "One image per page"
        }
    }
    let plainText = "Plain Text"
    let epubBook = "EPUB e-book"
    let pngImage = "PNG image"
    let jpegImage = "JPEG image"
    let pdfModeText = "Extract text (editable)"
    let pdfModeImages = "Whole pages as images (keeps layout)"

    func errUnsupportedInput(_ s: String) -> String { "Can’t read this format: \(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "Can’t write this format: \(s)" }
    func errInvalidFile(_ s: String) -> String { "The file is invalid or damaged: \(s)" }
    let errEmptyDocument = "The document has no content to convert"
    func errFailed(_ s: String) -> String { "Conversion failed: \(s)" }
    let noExtension = "(no file extension)"
    let pdfContextFailed = "Couldn’t create the PDF context"
    let pdfLayoutFailed = "PDF layout failed"
    let cannotOpenPDF = "Couldn’t open the PDF"
    let pdfEncrypted = "The PDF is encrypted and needs a password"
    func systemCannotParse(_ format: String) -> String { "macOS couldn’t read this \(format) file" }
    let libreOfficeNotFound = "LibreOffice not found"
    let libreOfficeTimeout = "LibreOffice timed out"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice produced no output file (exit code \(code))" }
    let notZip = "Not a valid ZIP container"
    let zipDirectoryMissing = "ZIP directory not found"
    func missingPart(_ name: String) -> String { "\(name) is missing" }
    let epubNoPackage = "EPUB package information is missing"
    let invalidJSON = "Malformed JSON"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[Image]" : "[Image: \(alt)]" }
    func pageN(_ n: Int) -> String { "Page \(n)" }
    func slideN(_ n: Int) -> String { "Slide \(n)" }
    func partN(_ n: Int) -> String { "Part \(n)" }
    func tableN(_ n: Int) -> String { "Table \(n)" }
    func columnN(_ n: Int) -> String { "Column \(n)" }
    let speakerNotes = "Speaker Notes"
    let chartPlaceholder = "[Chart]"
    let continuedSuffix = " (cont.)"
    let untitledDocument = "Document"
    let untitledPresentation = "Presentation"
    let sheetContent = "Content"
    let placeholderTitle = "Title"
    let placeholderSubtitle = "Subtitle"
    let placeholderBody = "Text"
    let pdfRasterizer = "PDF rasterizer"

    let cliUsage = "Usage: docconv -t <format> [options] <file...>"
    let cliOptions = "Options:"
    let cliTo = "Target format (required)"
    let cliOut = "Output folder (default: next to the original file)"
    let cliPage = "Page size (PDF/Word)"
    let cliLandscape = "Landscape orientation"
    let cliFontSize = "Body font size (default 11)"
    let cliMargin = "Page margin (default 56)"
    let cliPdfMode = "Reading PDF: extract text / whole pages as images"
    let cliNoOCR = "Don’t run text recognition on scanned pages"
    let cliSplit = "Heading level that starts a new slide (default 2)"
    let cliNotes = "Include speaker notes when reading PowerPoint"
    let cliEmbedImages = "Embed images in Markdown as data URIs"
    let cliDPI = "Image output resolution (default 150)"
    let cliLibreOffice = "Use LibreOffice, if installed, for high-fidelity Office → PDF"
    let cliLang = "Interface language: zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "Print the intermediate representation (debugging)"
    let cliVerbose = "Show debug logs from system frameworks"
    let cliFormats = "List supported formats"
    let cliHelp = "Show this help"
    let cliReadable = "Reads"
    let cliWritable = "Writes"
    let cliReadMark = "R"
    let cliWriteMark = "W"
    func cliUnknownFormat(_ s: String) -> String { "Unknown format: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "Unknown language: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "Unknown option: \(s)" }

    let usageFolders = "Reads the files you choose and saves the converted files next to them."
    let usageRemovable = "Reads and saves files on removable drives."
    let usageNetwork = "Reads and saves files on network drives."
}
