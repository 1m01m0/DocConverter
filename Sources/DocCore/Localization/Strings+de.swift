// Deutsch
struct StringsDe: LocalizedStrings {
    let listSeparator = ", "
    let appName = "Dokumentkonverter"

    let dropTitle = "Dateien hierher ziehen"
    let dropSubtitle = "Konvertiert zwischen PDF, Word, PowerPoint, Excel, Markdown, HTML, TXT, CSV, JSON, RTF, ODT, EPUB und Bildern"
    let chooseFiles = "Dateien auswählen …"
    let dropHint = "Auch ganze Ordner lassen sich hierher ziehen – oder Dateien auf das Dock-Symbol legen"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        shown < total ? "Nicht unterstützte Dateien ignoriert: \(list) und \(total - shown) weitere" : "Nicht unterstützte Dateien ignoriert: \(list)"
    }

    func fileCount(_ n: Int) -> String { n == 1 ? "1 Datei" : "\(n) Dateien" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "Konvertiere \(i) von \(n)" }
    let add = "Hinzufügen"
    let removeFinished = "Fertige entfernen"
    let clear = "Leeren"
    let revealSource = "Original im Finder zeigen"
    let revealResult = "Ergebnis im Finder zeigen"
    let openResult = "Ergebnis öffnen"
    let removeFromList = "Aus Liste entfernen"
    let unknownFormat = "Unbekanntes Format"
    let convertingStatus = "Wird konvertiert …"
    func skipped(_ reason: String) -> String { "Übersprungen: \(reason)" }
    let open = "Öffnen"
    let showInFinder = "Im Finder zeigen"

    let convertTo = "Konvertieren in"
    let saveTo = "Speichern"
    let chooseEllipsis = "Auswählen …"
    let advancedOptions = "Erweiterte Optionen"
    func outputsDone(_ n: Int) -> String { n == 1 ? "1 Datei erstellt" : "\(n) Dateien erstellt" }
    let convertingButton = "Konvertiere …"
    let startConvert = "Konvertieren"
    func startConvertCount(_ n: Int) -> String { "Konvertieren (\(n))" }
    func cannotConvertTo(_ format: String) -> String { "Die aktuellen Dateien lassen sich nicht in \(format) konvertieren" }

    let pageLabel = "Seite"
    let landscape = "Querformat"
    func bodyFontSize(_ pt: Int) -> String { "Text \(pt) pt" }
    let margins = "Ränder"
    let marginNarrow = "Schmal"
    let marginNormal = "Normal"
    let marginWide = "Breit"
    let readPDF = "PDF lesen"
    let ocrScannedPages = "Text in gescannten Seiten erkennen (OCR)"
    let slideSplitLabel = "Neue Folie bei"
    func headingLevel(_ n: Int) -> String { "Überschrift \(n)" }
    let includeSpeakerNotes = "Beim Lesen Notizen einbeziehen"
    let imagesLabel = "Bilder"
    let resolution = "Auflösung"
    let embedImagesInMarkdown = "Bilder in Markdown einbetten (kein _assets-Ordner)"
    let highFidelity = "Originaltreue"
    let useLibreOffice = "LibreOffice für Office → PDF verwenden (behält das Layout bei)"
    let libreOfficeMissing = "LibreOffice wurde nicht gefunden. Nach der Installation (libreoffice.org oder brew install --cask libreoffice) ist diese Option verfügbar."

    let language = "Sprache"
    func followSystem(_ resolved: String) -> String { "Systemsprache (\(resolved))" }
    let relaunchNote = "Systemmenüs wechseln die Sprache nach dem erneuten Öffnen der App"

    let sameAsSource = "Neben dem Original"
    let customFolder = "Eigener Ordner"
    let savedNextToSource = "Wird neben jeder Originaldatei gespeichert"
    let noFolderChosen = "Kein Ordner ausgewählt"
    let choosePrompt = "Auswählen"
    let chooseFolderMessage = "Speicherort für die konvertierten Dateien auswählen"
    let chooseFilesMessage = "Zu konvertierende Dateien auswählen (Ordner sind ebenfalls möglich)"

    let notePDFText = "Beim Konvertieren eines PDF in ein bearbeitbares Format werden Text und Struktur (Überschriften, Absätze, Listen, einfache Tabellen) übernommen; das ursprüngliche Layout bleibt nicht erhalten. Um das Aussehen zu bewahren, wähle in den erweiterten Optionen „Ganze Seiten als Bilder“."
    let notePDFImages = "Modus „Ganze Seiten als Bilder“: Das Ergebnis sieht aus wie das PDF, der Text ist aber nicht bearbeitbar."
    let noteTablesOnly = "Beim Export in eine Tabelle bleiben nur die Tabellen des Dokuments erhalten; Dokumente ohne Tabellen werden zeilenweise geschrieben."
    let noteSlides = "Folien werden an Überschriften geteilt (einstellbar in den erweiterten Optionen); langer Inhalt wird auf weiteren Folien fortgesetzt."
    let noteOfficePDFWithLibreOffice = "Die integrierte Engine setzt den Inhalt neu. Um das Office-Layout exakt zu erhalten, aktiviere LibreOffice in den erweiterten Optionen."
    let noteOfficePDFNoLibreOffice = "Die integrierte Engine setzt den Inhalt neu und behält das ursprüngliche Office-Layout nicht bei (mit installiertem LibreOffice ist der originaltreue Modus verfügbar)."

    func alreadyFormat(_ format: String) -> String { "bereits im Format \(format)" }
    func unsupportedTarget(_ format: String) -> String { "kann nicht in \(format) konvertiert werden" }

    let addFilesMenu = "Dateien hinzufügen …"
    let convertMenu = "Konvertieren"
    let startConvertMenu = "Konvertierung starten"
    let chooseSaveLocationMenu = "Speicherort auswählen …"
    let clearListMenu = "Liste leeren"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "Portables Dokument"
        case .docx: return "Word-Dokument"
        case .doc: return "Word 97–2003"
        case .pptx: return "Präsentation"
        case .xlsx: return "Tabelle"
        case .md: return "Auszeichnung"
        case .html: return "Webseite"
        case .txt: return "Reiner Text"
        case .csv: return "Kommagetrennt"
        case .tsv: return "Tabulatorgetrennt"
        case .json: return "Strukturierte Daten"
        case .rtf: return "Formatierter Text"
        case .odt: return "OpenDocument"
        case .epub: return "E-Book"
        case .tex: return "LaTeX-Quelltext"
        case .png, .jpg: return "Ein Bild pro Seite"
        }
    }
    let plainText = "Reiner Text"
    let epubBook = "EPUB-E-Book"
    let pngImage = "PNG-Bild"
    let jpegImage = "JPEG-Bild"
    let pdfModeText = "Text extrahieren (bearbeitbar)"
    let pdfModeImages = "Ganze Seiten als Bilder (Layout bleibt)"

    func errUnsupportedInput(_ s: String) -> String { "Dieses Format kann nicht gelesen werden: \(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "In dieses Format kann nicht geschrieben werden: \(s)" }
    func errInvalidFile(_ s: String) -> String { "Die Datei ist ungültig oder beschädigt: \(s)" }
    let errEmptyDocument = "Das Dokument enthält keinen konvertierbaren Inhalt"
    func errFailed(_ s: String) -> String { "Konvertierung fehlgeschlagen: \(s)" }
    let noExtension = "(keine Dateiendung)"
    let pdfContextFailed = "PDF-Kontext konnte nicht erstellt werden"
    let pdfLayoutFailed = "PDF-Satz fehlgeschlagen"
    let cannotOpenPDF = "PDF konnte nicht geöffnet werden"
    let pdfEncrypted = "Das PDF ist verschlüsselt und erfordert ein Passwort"
    func systemCannotParse(_ format: String) -> String { "macOS kann diese \(format)-Datei nicht lesen" }
    let libreOfficeNotFound = "LibreOffice nicht gefunden"
    let libreOfficeTimeout = "Zeitüberschreitung bei LibreOffice"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice hat keine Ausgabedatei erzeugt (Exit-Code \(code))" }
    let notZip = "Kein gültiger ZIP-Container"
    let zipDirectoryMissing = "ZIP-Verzeichnis nicht gefunden"
    func missingPart(_ name: String) -> String { "\(name) fehlt" }
    let epubNoPackage = "EPUB-Paketinformationen fehlen"
    let invalidJSON = "Fehlerhaftes JSON"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[Bild]" : "[Bild: \(alt)]" }
    func pageN(_ n: Int) -> String { "Seite \(n)" }
    func slideN(_ n: Int) -> String { "Folie \(n)" }
    func partN(_ n: Int) -> String { "Teil \(n)" }
    func tableN(_ n: Int) -> String { "Tabelle \(n)" }
    func columnN(_ n: Int) -> String { "Spalte \(n)" }
    let speakerNotes = "Notizen"
    let chartPlaceholder = "[Diagramm]"
    let continuedSuffix = " (Forts.)"
    let untitledDocument = "Dokument"
    let untitledPresentation = "Präsentation"
    let sheetContent = "Inhalt"
    let placeholderTitle = "Titel"
    let placeholderSubtitle = "Untertitel"
    let placeholderBody = "Text"
    let pdfRasterizer = "PDF-Rasterung"

    let cliUsage = "Verwendung: docconv -t <Format> [Optionen] <Datei...>"
    let cliOptions = "Optionen:"
    let cliTo = "Zielformat (erforderlich)"
    let cliOut = "Ausgabeordner (Standard: neben dem Original)"
    let cliPage = "Seitengröße (PDF/Word)"
    let cliLandscape = "Querformat"
    let cliFontSize = "Schriftgröße des Textes (Standard 11)"
    let cliMargin = "Seitenrand (Standard 56)"
    let cliPdfMode = "PDF lesen: Text extrahieren / ganze Seiten als Bilder"
    let cliNoOCR = "Keine Texterkennung für gescannte Seiten"
    let cliSplit = "Überschriftenebene, die eine neue Folie beginnt (Standard 2)"
    let cliNotes = "Beim Lesen von PowerPoint Notizen einbeziehen"
    let cliEmbedImages = "Bilder in Markdown als Data-URI einbetten"
    let cliDPI = "Auflösung der Bildausgabe (Standard 150)"
    let cliLibreOffice = "LibreOffice (falls installiert) für originaltreues Office → PDF verwenden"
    let cliLang = "Sprache der Oberfläche: zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "Zwischendarstellung ausgeben (Debugging)"
    let cliVerbose = "Debug-Protokolle der System-Frameworks anzeigen"
    let cliFormats = "Unterstützte Formate auflisten"
    let cliHelp = "Diese Hilfe anzeigen"
    let cliReadable = "Lesen"
    let cliWritable = "Schreiben"
    let cliReadMark = "L"
    let cliWriteMark = "S"
    func cliUnknownFormat(_ s: String) -> String { "Unbekanntes Format: \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "Unbekannte Sprache: \(s)" }
    func cliUnknownOption(_ s: String) -> String { "Unbekannte Option: \(s)" }

    let usageFolders = "Liest die ausgewählten Dateien und speichert die konvertierten Dateien daneben."
    let usageRemovable = "Liest und speichert Dateien auf Wechseldatenträgern."
    let usageNetwork = "Liest und speichert Dateien auf Netzlaufwerken."
}
