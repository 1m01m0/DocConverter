// 한국어
struct StringsKo: LocalizedStrings {
    let listSeparator = ", "
    let appName = "문서 변환기"

    let dropTitle = "여기에 파일을 끌어다 놓으세요"
    let dropSubtitle = "PDF, Word, PowerPoint, Excel, Markdown, HTML, TXT, CSV, JSON, RTF, ODT, EPUB, 이미지를 서로 변환"
    let chooseFiles = "파일 선택…"
    let dropHint = "폴더 전체를 끌어다 놓거나 Dock 아이콘에 파일을 놓아도 됩니다"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "지원하지 않는 파일을 건너뛰었습니다: \(list) 외 \(total - shown)개" : "지원하지 않는 파일을 건너뛰었습니다: \(list)"
    }

    func fileCount(_ n: Int) -> String { "파일 \(n)개" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "변환 중 \(i)/\(n)" }
    let add = "추가"
    let removeFinished = "완료 항목 제거"
    let clear = "모두 지우기"
    let revealSource = "Finder에서 원본 보기"
    let revealResult = "Finder에서 결과 보기"
    let openResult = "결과 열기"
    let removeFromList = "목록에서 제거"
    let unknownFormat = "알 수 없는 형식"
    let convertingStatus = "변환 중…"
    func skipped(_ reason: String) -> String { "건너뜀: \(reason)" }
    let open = "열기"
    let showInFinder = "Finder에서 보기"

    let convertTo = "변환할 형식"
    let saveTo = "저장 위치"
    let chooseEllipsis = "선택…"
    let advancedOptions = "고급 옵션"
    func outputsDone(_ n: Int) -> String { "파일 \(n)개 생성 완료" }
    let convertingButton = "변환 중…"
    let startConvert = "변환 시작"
    func startConvertCount(_ n: Int) -> String { "변환 시작(\(n))" }
    func cannotConvertTo(_ format: String) -> String { "현재 파일은 \(format) 형식으로 변환할 수 없습니다" }

    let pageLabel = "페이지"
    let landscape = "가로 방향"
    func bodyFontSize(_ pt: Int) -> String { "본문 \(pt)pt" }
    let margins = "여백"
    let marginNarrow = "좁게"
    let marginNormal = "보통"
    let marginWide = "넓게"
    let readPDF = "PDF 읽기"
    let ocrScannedPages = "스캔 페이지 텍스트 인식(OCR)"
    let slideSplitLabel = "슬라이드 나누기 기준"
    func headingLevel(_ n: Int) -> String { "제목 \(n)" }
    let includeSpeakerNotes = "읽을 때 발표자 노트 포함"
    let imagesLabel = "이미지"
    let resolution = "해상도"
    let embedImagesInMarkdown = "Markdown에 이미지 포함(_assets 폴더를 만들지 않음)"
    let highFidelity = "원본 유지"
    let useLibreOffice = "LibreOffice로 Office → PDF 변환(원본 레이아웃 유지)"
    let libreOfficeMissing = "LibreOffice를 찾을 수 없습니다. 설치하면(libreoffice.org 또는 brew install --cask libreoffice) 사용할 수 있습니다."

    let language = "언어"
    func followSystem(_ resolved: String) -> String { "시스템 설정 따르기(\(resolved))" }
    let relaunchNote = "시스템 메뉴는 앱을 다시 열면 바뀝니다"

    let sameAsSource = "원본과 같은 위치"
    let customFolder = "폴더 지정"
    let savedNextToSource = "각 원본 파일 옆에 저장"
    let noFolderChosen = "폴더를 선택하지 않음"
    let choosePrompt = "선택"
    let chooseFolderMessage = "변환 결과를 저장할 위치를 선택하세요"
    let chooseFilesMessage = "변환할 파일을 선택하세요(폴더도 선택할 수 있습니다)"

    let notePDFText = "PDF를 편집 가능한 형식으로 변환하면 텍스트와 구조(제목, 단락, 목록, 간단한 표)를 추출하며 원래 레이아웃은 유지되지 않습니다. 모양을 유지하려면 ‘고급 옵션’에서 ‘페이지 전체를 이미지로’를 선택하세요."
    let notePDFImages = "‘페이지 전체를 이미지로’ 모드: 원본 PDF와 똑같이 보이지만 텍스트는 편집할 수 없습니다."
    let noteTablesOnly = "스프레드시트로 내보내면 문서의 표만 남습니다. 표가 없는 문서는 텍스트를 한 줄씩 기록합니다."
    let noteSlides = "제목을 기준으로 슬라이드를 자동으로 나눕니다(‘고급 옵션’에서 변경 가능). 긴 내용은 다음 슬라이드로 이어집니다."
    let noteOfficePDFWithLibreOffice = "내장 엔진은 내용을 다시 배치합니다. Office 원본 레이아웃을 그대로 유지하려면 ‘고급 옵션’에서 LibreOffice를 켜세요."
    let noteOfficePDFNoLibreOffice = "내장 엔진은 내용을 다시 배치하므로 Office 파일의 원래 레이아웃은 유지되지 않습니다(LibreOffice를 설치하면 원본 유지 모드를 사용할 수 있습니다)."

    func alreadyFormat(_ format: String) -> String { "이미 \(format) 형식입니다" }
    func unsupportedTarget(_ format: String) -> String { "\(format) 형식으로 변환할 수 없습니다" }

    let addFilesMenu = "파일 추가…"
    let convertMenu = "변환"
    let startConvertMenu = "변환 시작"
    let chooseSaveLocationMenu = "저장 위치 선택…"
    let clearListMenu = "목록 지우기"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "휴대용 문서"
        case .docx: return "Word 문서"
        case .doc: return "Word 97-2003"
        case .pptx: return "프레젠테이션"
        case .xlsx: return "스프레드시트"
        case .md: return "경량 마크업"
        case .html: return "웹 페이지"
        case .txt: return "일반 텍스트"
        case .csv: return "쉼표로 구분"
        case .tsv: return "탭으로 구분"
        case .json: return "구조화 데이터"
        case .rtf: return "서식 있는 텍스트"
        case .odt: return "OpenDocument"
        case .epub: return "전자책"
        case .tex: return "LaTeX 소스"
        case .png, .jpg: return "페이지당 이미지 1장"
        }
    }
    let plainText = "일반 텍스트"
    let epubBook = "EPUB 전자책"
    let pngImage = "PNG 이미지"
    let jpegImage = "JPEG 이미지"
    let pdfModeText = "텍스트 추출(편집 가능)"
    let pdfModeImages = "페이지 전체를 이미지로(레이아웃 유지)"

    func errUnsupportedInput(_ s: String) -> String { "이 형식은 읽을 수 없습니다: \(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "이 형식으로 내보낼 수 없습니다: \(s)" }
    func errInvalidFile(_ s: String) -> String { "파일이 올바르지 않거나 손상되었습니다: \(s)" }
    let errEmptyDocument = "문서에 변환할 내용이 없습니다"
    func errFailed(_ s: String) -> String { "변환 실패: \(s)" }
    let noExtension = "(확장자 없음)"
    let pdfContextFailed = "PDF 컨텍스트를 만들 수 없습니다"
    let pdfLayoutFailed = "PDF 레이아웃에 실패했습니다"
    let cannotOpenPDF = "PDF를 열 수 없습니다"
    let pdfEncrypted = "PDF가 암호화되어 있어 암호가 필요합니다"
    func systemCannotParse(_ format: String) -> String { "시스템에서 이 \(format) 파일을 해석할 수 없습니다" }
    let libreOfficeNotFound = "LibreOffice를 찾을 수 없습니다"
    let libreOfficeTimeout = "LibreOffice 변환 시간이 초과되었습니다"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice가 출력 파일을 만들지 않았습니다(종료 코드 \(code))" }
    let notZip = "올바른 ZIP 컨테이너가 아닙니다"
    let zipDirectoryMissing = "ZIP 디렉터리를 찾을 수 없습니다"
    func missingPart(_ name: String) -> String { "\(name) 파일이 없습니다" }
    let epubNoPackage = "EPUB 패키지 정보가 없습니다"
    let invalidJSON = "JSON 형식이 잘못되었습니다"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[이미지]" : "[이미지: \(alt)]" }
    func pageN(_ n: Int) -> String { "\(n)페이지" }
    func slideN(_ n: Int) -> String { "슬라이드 \(n)" }
    func partN(_ n: Int) -> String { "\(n)부" }
    func tableN(_ n: Int) -> String { "표 \(n)" }
    func columnN(_ n: Int) -> String { "열 \(n)" }
    let speakerNotes = "발표자 노트"
    let chartPlaceholder = "[차트]"
    let continuedSuffix = " (계속)"
    let untitledDocument = "문서"
    let untitledPresentation = "프레젠테이션"
    let sheetContent = "내용"
    let placeholderTitle = "제목"
    let placeholderSubtitle = "부제목"
    let placeholderBody = "본문"
    let pdfRasterizer = "PDF 래스터화"

    let cliUsage = "사용법: docconv -t <형식> [옵션] <파일...>"
    let cliOptions = "옵션:"
    let cliTo = "변환할 형식(필수)"
    let cliOut = "출력 폴더(기본값: 원본 파일과 같은 위치)"
    let cliPage = "용지 크기(PDF/Word)"
    let cliLandscape = "가로 방향"
    let cliFontSize = "본문 글자 크기(기본값 11)"
    let cliMargin = "여백(기본값 56)"
    let cliPdfMode = "PDF 읽기: 텍스트 추출 / 페이지 전체를 이미지로"
    let cliNoOCR = "스캔 페이지에서 텍스트 인식을 하지 않음"
    let cliSplit = "새 슬라이드를 시작할 제목 수준(기본값 2)"
    let cliNotes = "PowerPoint를 읽을 때 발표자 노트 포함"
    let cliEmbedImages = "Markdown 이미지를 data URI로 포함"
    let cliDPI = "이미지 출력 해상도(기본값 150)"
    let cliLibreOffice = "LibreOffice가 설치되어 있으면 Office → PDF를 원본대로 변환"
    let cliLang = "인터페이스 언어: zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "중간 표현 출력(디버깅용)"
    let cliVerbose = "시스템 프레임워크의 디버그 로그 표시"
    let cliFormats = "지원 형식 목록"
    let cliHelp = "이 도움말 표시"
    let cliReadable = "읽기"
    let cliWritable = "쓰기"
    let cliReadMark = "읽"
    let cliWriteMark = "쓰"
    func cliUnknownFormat(_ s: String) -> String { "알 수 없는 형식: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "알 수 없는 언어: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "알 수 없는 옵션: \(s)" }

    let usageFolders = "선택한 파일을 읽고 변환 결과를 원본 파일 옆에 저장합니다."
    let usageRemovable = "이동식 디스크의 파일을 읽고 저장합니다."
    let usageNetwork = "네트워크 디스크의 파일을 읽고 저장합니다."
}
