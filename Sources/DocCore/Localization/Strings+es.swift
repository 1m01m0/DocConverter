// Español
struct StringsEs: LocalizedStrings {
    let listSeparator = ", "
    let appName = "Conversor de documentos"

    let dropTitle = "Arrastra archivos aquí"
    let dropSubtitle = "Convierte entre PDF, Word, PowerPoint, Excel, Markdown, HTML, TXT, CSV, JSON, RTF, ODT, EPUB e imágenes"
    let chooseFiles = "Elegir archivos…"
    let dropHint = "También puedes arrastrar una carpeta entera o soltar archivos en el icono del Dock"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "Archivos no compatibles ignorados: \(list) y \(total - shown) más" : "Archivos no compatibles ignorados: \(list)"
    }

    func fileCount(_ n: Int) -> String { n == 1 ? "1 archivo" : "\(n) archivos" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "Convirtiendo \(i) de \(n)" }
    let add = "Añadir"
    let removeFinished = "Quitar terminados"
    let clear = "Vaciar"
    let revealSource = "Mostrar original en Finder"
    let revealResult = "Mostrar resultado en Finder"
    let openResult = "Abrir resultado"
    let removeFromList = "Quitar de la lista"
    let unknownFormat = "Formato desconocido"
    let convertingStatus = "Convirtiendo…"
    func skipped(_ reason: String) -> String { "Omitido: \(reason)" }
    let open = "Abrir"
    let showInFinder = "Mostrar en Finder"

    let convertTo = "Convertir a"
    let saveTo = "Guardar en"
    let chooseEllipsis = "Elegir…"
    let advancedOptions = "Opciones avanzadas"
    func outputsDone(_ n: Int) -> String { n == 1 ? "1 archivo creado" : "\(n) archivos creados" }
    let convertingButton = "Convirtiendo…"
    let startConvert = "Convertir"
    func startConvertCount(_ n: Int) -> String { "Convertir (\(n))" }
    func cannotConvertTo(_ format: String) -> String { "Los archivos actuales no se pueden convertir a \(format)" }

    let pageLabel = "Página"
    let landscape = "Horizontal"
    func bodyFontSize(_ pt: Int) -> String { "Cuerpo \(pt) pt" }
    let margins = "Márgenes"
    let marginNarrow = "Estrechos"
    let marginNormal = "Normales"
    let marginWide = "Anchos"
    let readPDF = "Lectura de PDF"
    let ocrScannedPages = "Reconocer texto en páginas escaneadas (OCR)"
    let slideSplitLabel = "Nueva diapositiva en"
    func headingLevel(_ n: Int) -> String { "Título \(n)" }
    let includeSpeakerNotes = "Incluir notas del orador al leer"
    let imagesLabel = "Imágenes"
    let resolution = "Resolución"
    let embedImagesInMarkdown = "Incrustar imágenes en Markdown (sin carpeta _assets)"
    let highFidelity = "Alta fidelidad"
    let useLibreOffice = "Usar LibreOffice para Office → PDF (conserva el diseño original)"
    let libreOfficeMissing = "No se encontró LibreOffice. Instálalo (libreoffice.org o brew install --cask libreoffice) para activar esta opción."

    let language = "Idioma"
    func followSystem(_ resolved: String) -> String { "Idioma del sistema (\(resolved))" }
    let relaunchNote = "Los menús del sistema cambian de idioma al volver a abrir la app"

    let sameAsSource = "Junto al original"
    let customFolder = "Carpeta elegida"
    let savedNextToSource = "Se guarda junto a cada archivo original"
    let noFolderChosen = "Ninguna carpeta elegida"
    let choosePrompt = "Elegir"
    let chooseFolderMessage = "Elige dónde guardar los archivos convertidos"
    let chooseFilesMessage = "Elige los archivos que quieres convertir (también carpetas)"

    let notePDFText = "Al convertir un PDF a un formato editable se extraen el texto y la estructura (títulos, párrafos, listas, tablas sencillas); no se conserva el diseño original. Para mantener el aspecto, elige «Páginas como imágenes» en Opciones avanzadas."
    let notePDFImages = "Modo «Páginas como imágenes»: el resultado se ve igual que el PDF, pero el texto no se puede editar."
    let noteTablesOnly = "Al exportar a una hoja de cálculo solo se conservan las tablas; los documentos sin tablas se escriben línea por línea."
    let noteSlides = "Las diapositivas se dividen en los títulos (ajustable en Opciones avanzadas); el contenido largo continúa en diapositivas adicionales."
    let noteOfficePDFWithLibreOffice = "El motor integrado vuelve a maquetar el contenido. Para conservar exactamente el diseño de Office, activa LibreOffice en Opciones avanzadas."
    let noteOfficePDFNoLibreOffice = "El motor integrado vuelve a maquetar el contenido y no conserva el diseño original de Office (instala LibreOffice para activar el modo de alta fidelidad)."

    func alreadyFormat(_ format: String) -> String { "ya está en formato \(format)" }
    func unsupportedTarget(_ format: String) -> String { "no se puede convertir a \(format)" }

    let addFilesMenu = "Añadir archivos…"
    let convertMenu = "Convertir"
    let startConvertMenu = "Iniciar conversión"
    let chooseSaveLocationMenu = "Elegir ubicación…"
    let clearListMenu = "Vaciar lista"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "Documento portátil"
        case .docx: return "Documento Word"
        case .doc: return "Word 97-2003"
        case .pptx: return "Presentación"
        case .xlsx: return "Hoja de cálculo"
        case .md: return "Marcado ligero"
        case .html: return "Página web"
        case .txt: return "Texto sin formato"
        case .csv: return "Separado por comas"
        case .tsv: return "Separado por tabs"
        case .json: return "Datos estructurados"
        case .rtf: return "Texto enriquecido"
        case .odt: return "OpenDocument"
        case .epub: return "Libro electrónico"
        case .tex: return "Código LaTeX"
        case .png, .jpg: return "Imagen por página"
        }
    }
    let plainText = "Texto sin formato"
    let epubBook = "Libro EPUB"
    let pngImage = "Imagen PNG"
    let jpegImage = "Imagen JPEG"
    let pdfModeText = "Extraer texto (editable)"
    let pdfModeImages = "Páginas como imágenes (conserva el diseño)"

    func errUnsupportedInput(_ s: String) -> String { "No se puede leer este formato: \(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "No se puede escribir este formato: \(s)" }
    func errInvalidFile(_ s: String) -> String { "El archivo no es válido o está dañado: \(s)" }
    let errEmptyDocument = "El documento no tiene contenido que convertir"
    func errFailed(_ s: String) -> String { "Error de conversión: \(s)" }
    let noExtension = "(sin extensión)"
    let pdfContextFailed = "No se pudo crear el contexto PDF"
    let pdfLayoutFailed = "Error al maquetar el PDF"
    let cannotOpenPDF = "No se pudo abrir el PDF"
    let pdfEncrypted = "El PDF está cifrado y requiere una contraseña"
    func systemCannotParse(_ format: String) -> String { "macOS no puede leer este archivo \(format)" }
    let libreOfficeNotFound = "No se encontró LibreOffice"
    let libreOfficeTimeout = "LibreOffice superó el tiempo de espera"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice no generó ningún archivo (código de salida \(code))" }
    let notZip = "No es un contenedor ZIP válido"
    let zipDirectoryMissing = "No se encontró el directorio ZIP"
    func missingPart(_ name: String) -> String { "Falta \(name)" }
    let epubNoPackage = "Falta la información del paquete EPUB"
    let invalidJSON = "JSON mal formado"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[Imagen]" : "[Imagen: \(alt)]" }
    func pageN(_ n: Int) -> String { "Página \(n)" }
    func slideN(_ n: Int) -> String { "Diapositiva \(n)" }
    func partN(_ n: Int) -> String { "Parte \(n)" }
    func tableN(_ n: Int) -> String { "Tabla \(n)" }
    func columnN(_ n: Int) -> String { "Columna \(n)" }
    let speakerNotes = "Notas del orador"
    let chartPlaceholder = "[Gráfico]"
    let continuedSuffix = " (cont.)"
    let untitledDocument = "Documento"
    let untitledPresentation = "Presentación"
    let sheetContent = "Contenido"
    let placeholderTitle = "Título"
    let placeholderSubtitle = "Subtítulo"
    let placeholderBody = "Texto"
    let pdfRasterizer = "Rasterizado de PDF"

    let cliUsage = "Uso: docconv -t <formato> [opciones] <archivo...>"
    let cliOptions = "Opciones:"
    let cliTo = "Formato de destino (obligatorio)"
    let cliOut = "Carpeta de salida (por omisión: junto al original)"
    let cliPage = "Tamaño de página (PDF/Word)"
    let cliLandscape = "Orientación horizontal"
    let cliFontSize = "Tamaño del texto (por omisión 11)"
    let cliMargin = "Margen de página (por omisión 56)"
    let cliPdfMode = "Lectura de PDF: extraer texto / páginas como imágenes"
    let cliNoOCR = "No reconocer texto en páginas escaneadas"
    let cliSplit = "Nivel de título que inicia una diapositiva (por omisión 2)"
    let cliNotes = "Incluir notas del orador al leer PowerPoint"
    let cliEmbedImages = "Incrustar imágenes en Markdown como data URI"
    let cliDPI = "Resolución de las imágenes (por omisión 150)"
    let cliLibreOffice = "Usar LibreOffice, si está instalado, para Office → PDF de alta fidelidad"
    let cliLang = "Idioma de la interfaz: zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "Mostrar la representación intermedia (depuración)"
    let cliVerbose = "Mostrar registros de depuración de los frameworks del sistema"
    let cliFormats = "Listar los formatos compatibles"
    let cliHelp = "Mostrar esta ayuda"
    let cliReadable = "Lee"
    let cliWritable = "Escribe"
    let cliReadMark = "L"
    let cliWriteMark = "E"
    func cliUnknownFormat(_ s: String) -> String { "Formato desconocido: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "Idioma desconocido: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "Opción desconocida: \(s)" }

    let usageFolders = "Lee los archivos que eliges y guarda los archivos convertidos junto a ellos."
    let usageRemovable = "Lee y guarda archivos en discos extraíbles."
    let usageNetwork = "Lee y guarda archivos en discos de red."
}
