// Français
struct StringsFr: LocalizedStrings {
    let listSeparator = ", "
    let appName = "Convertisseur de documents"

    let dropTitle = "Déposez vos fichiers ici"
    let dropSubtitle = "Convertissez entre PDF, Word, PowerPoint, Excel, Markdown, HTML, TXT, CSV, JSON, RTF, ODT, EPUB et images"
    let chooseFiles = "Choisir des fichiers…"
    let dropHint = "Vous pouvez aussi déposer un dossier entier, ou déposer des fichiers sur l’icône du Dock"
    func ignoredFiles(_ list: String, shown: Int, total: Int) -> String {
        let others = total - shown
        if others <= 0 { return "Fichiers non pris en charge ignorés : \(list)" }
        return "Fichiers non pris en charge ignorés : \(list) et \(others) \(others == 1 ? "autre" : "autres")"
    }

    func fileCount(_ n: Int) -> String { n <= 1 ? "\(n) fichier" : "\(n) fichiers" }
    func convertingProgress(_ i: Int, _ n: Int) -> String { "Conversion \(i) sur \(n)" }
    let add = "Ajouter"
    let removeFinished = "Retirer les terminés"
    let clear = "Tout effacer"
    let revealSource = "Afficher l’original dans le Finder"
    let revealResult = "Afficher le résultat dans le Finder"
    let openResult = "Ouvrir le résultat"
    let removeFromList = "Retirer de la liste"
    let unknownFormat = "Format inconnu"
    let convertingStatus = "Conversion…"
    func skipped(_ reason: String) -> String { "Ignoré : \(reason)" }
    let open = "Ouvrir"
    let showInFinder = "Afficher dans le Finder"

    let convertTo = "Convertir en"
    let saveTo = "Enregistrer"
    let chooseEllipsis = "Choisir…"
    let advancedOptions = "Options avancées"
    func outputsDone(_ n: Int) -> String { n <= 1 ? "\(n) fichier créé" : "\(n) fichiers créés" }
    let convertingButton = "Conversion…"
    let startConvert = "Convertir"
    func startConvertCount(_ n: Int) -> String { "Convertir (\(n))" }
    func cannotConvertTo(_ format: String) -> String { "Les fichiers actuels ne peuvent pas être convertis en \(format)" }

    let pageLabel = "Page"
    let landscape = "Paysage"
    func bodyFontSize(_ pt: Int) -> String { "Corps \(pt) pt" }
    let margins = "Marges"
    let marginNarrow = "Étroites"
    let marginNormal = "Normales"
    let marginWide = "Larges"
    let readPDF = "Lecture PDF"
    let ocrScannedPages = "Reconnaître le texte des pages numérisées (OCR)"
    let slideSplitLabel = "Nouvelle diapo à chaque"
    func headingLevel(_ n: Int) -> String { "Titre \(n)" }
    let includeSpeakerNotes = "Inclure les notes du présentateur à la lecture"
    let imagesLabel = "Images"
    let resolution = "Résolution"
    let embedImagesInMarkdown = "Intégrer les images au Markdown (sans dossier _assets)"
    let highFidelity = "Haute fidélité"
    let useLibreOffice = "Utiliser LibreOffice pour Office → PDF (conserve la mise en page)"
    let libreOfficeMissing = "LibreOffice est introuvable. Installez-le (libreoffice.org ou brew install --cask libreoffice) pour activer cette option."

    let language = "Langue"
    func followSystem(_ resolved: String) -> String { "Langue du système (\(resolved))" }
    let relaunchNote = "Les menus système changent de langue à la réouverture de l’app"

    let sameAsSource = "À côté de l’original"
    let customFolder = "Dossier choisi"
    let savedNextToSource = "Enregistré à côté de chaque fichier d’origine"
    let noFolderChosen = "Aucun dossier choisi"
    let choosePrompt = "Choisir"
    let chooseFolderMessage = "Choisissez où enregistrer les fichiers convertis"
    let chooseFilesMessage = "Choisissez les fichiers à convertir (les dossiers sont acceptés)"

    let notePDFText = "La conversion d’un PDF en format modifiable extrait le texte et la structure (titres, paragraphes, listes, tableaux simples) ; la mise en page d’origine n’est pas conservée. Pour garder l’apparence, choisissez « Pages en images » dans les options avancées."
    let notePDFImages = "Mode « Pages en images » : le résultat est identique au PDF, mais le texte n’est pas modifiable."
    let noteTablesOnly = "L’export vers un tableur ne conserve que les tableaux ; les documents sans tableau sont écrits ligne par ligne."
    let noteSlides = "Les diapositives sont découpées aux titres (réglable dans les options avancées) ; un contenu trop long continue sur d’autres diapositives."
    let noteOfficePDFWithLibreOffice = "Le moteur intégré remet le contenu en page. Pour conserver exactement la mise en page Office, activez LibreOffice dans les options avancées."
    let noteOfficePDFNoLibreOffice = "Le moteur intégré remet le contenu en page et ne conserve pas la mise en page Office d’origine (installez LibreOffice pour activer le mode haute fidélité)."

    func alreadyFormat(_ format: String) -> String { "déjà au format \(format)" }
    func unsupportedTarget(_ format: String) -> String { "conversion en \(format) impossible" }

    let addFilesMenu = "Ajouter des fichiers…"
    let convertMenu = "Conversion"
    let startConvertMenu = "Lancer la conversion"
    let chooseSaveLocationMenu = "Choisir l’emplacement…"
    let clearListMenu = "Vider la liste"

    func targetSubtitle(_ format: Format) -> String {
        switch format {
        case .pdf: return "Document portable"
        case .docx: return "Document Word"
        case .doc: return "Word 97-2003"
        case .pptx: return "Présentation"
        case .xlsx: return "Tableur"
        case .md: return "Balisage léger"
        case .html: return "Page web"
        case .txt: return "Texte brut"
        case .csv: return "Virgules"
        case .tsv: return "Tabulations"
        case .json: return "Données structurées"
        case .rtf: return "Texte enrichi"
        case .odt: return "OpenDocument"
        case .epub: return "Livre numérique"
        case .tex: return "Source LaTeX"
        case .png, .jpg: return "Une image par page"
        }
    }
    let plainText = "Texte brut"
    let epubBook = "Livre EPUB"
    let pngImage = "Image PNG"
    let jpegImage = "Image JPEG"
    let pdfModeText = "Extraire le texte (modifiable)"
    let pdfModeImages = "Pages en images (mise en page conservée)"

    func errUnsupportedInput(_ s: String) -> String { "Impossible de lire ce format : \(s)" }
    func errUnsupportedOutput(_ s: String) -> String { "Impossible d’écrire ce format : \(s)" }
    func errInvalidFile(_ s: String) -> String { "Fichier non valide ou endommagé : \(s)" }
    let errEmptyDocument = "Le document ne contient rien à convertir"
    func errFailed(_ s: String) -> String { "Échec de la conversion : \(s)" }
    let noExtension = "(sans extension)"
    let pdfContextFailed = "Impossible de créer le contexte PDF"
    let pdfLayoutFailed = "Échec de la mise en page PDF"
    let cannotOpenPDF = "Impossible d’ouvrir le PDF"
    let pdfEncrypted = "Le PDF est chiffré et nécessite un mot de passe"
    func systemCannotParse(_ format: String) -> String { "macOS ne parvient pas à lire ce fichier \(format)" }
    let libreOfficeNotFound = "LibreOffice introuvable"
    let libreOfficeTimeout = "Délai dépassé pour LibreOffice"
    func libreOfficeNoOutput(_ code: Int32) -> String { "LibreOffice n’a produit aucun fichier (code de sortie \(code))" }
    let notZip = "Conteneur ZIP non valide"
    let zipDirectoryMissing = "Répertoire ZIP introuvable"
    func missingPart(_ name: String) -> String { "\(name) manquant" }
    let epubNoPackage = "Informations du paquet EPUB manquantes"
    let invalidJSON = "JSON mal formé"

    func imagePlaceholder(_ alt: String) -> String { alt.isEmpty ? "[Image]" : "[Image : \(alt)]" }
    func pageN(_ n: Int) -> String { "Page \(n)" }
    func slideN(_ n: Int) -> String { "Diapositive \(n)" }
    func partN(_ n: Int) -> String { "Partie \(n)" }
    func tableN(_ n: Int) -> String { "Tableau \(n)" }
    func columnN(_ n: Int) -> String { "Colonne \(n)" }
    let speakerNotes = "Notes du présentateur"
    let chartPlaceholder = "[Graphique]"
    let continuedSuffix = " (suite)"
    let untitledDocument = "Document"
    let untitledPresentation = "Présentation"
    let sheetContent = "Contenu"
    let placeholderTitle = "Titre"
    let placeholderSubtitle = "Sous-titre"
    let placeholderBody = "Texte"
    let pdfRasterizer = "Rastérisation PDF"

    let cliUsage = "Utilisation : docconv -t <format> [options] <fichier...>"
    let cliOptions = "Options :"
    let cliTo = "Format cible (obligatoire)"
    let cliOut = "Dossier de sortie (par défaut : à côté de l’original)"
    let cliPage = "Format de page (PDF/Word)"
    let cliLandscape = "Orientation paysage"
    let cliFontSize = "Taille du corps de texte (11 par défaut)"
    let cliMargin = "Marges (56 par défaut)"
    let cliPdfMode = "Lecture PDF : extraire le texte / pages en images"
    let cliNoOCR = "Ne pas reconnaître le texte des pages numérisées"
    let cliSplit = "Niveau de titre qui commence une diapositive (2 par défaut)"
    let cliNotes = "Inclure les notes du présentateur à la lecture d’un PowerPoint"
    let cliEmbedImages = "Intégrer les images au Markdown en data URI"
    let cliDPI = "Résolution des images produites (150 par défaut)"
    let cliLibreOffice = "Utiliser LibreOffice, s’il est installé, pour Office → PDF haute fidélité"
    let cliLang = "Langue de l’interface : zh-Hans zh-Hant en ja ko fr de es"
    let cliDump = "Afficher la représentation intermédiaire (débogage)"
    let cliVerbose = "Afficher les journaux de débogage des frameworks système"
    let cliFormats = "Lister les formats pris en charge"
    let cliHelp = "Afficher cette aide"
    let cliReadable = "Lecture"
    let cliWritable = "Écriture"
    let cliReadMark = "L"
    let cliWriteMark = "É"
    func cliUnknownFormat(_ s: String) -> String { "Format inconnu : \(s)" }
    func cliUnknownLanguage(_ s: String) -> String { "Langue inconnue : \(s)" }
    func cliUnknownOption(_ s: String) -> String { "Option inconnue : \(s)" }

    let usageFolders = "Lit les fichiers que vous choisissez et enregistre les fichiers convertis à côté."
    let usageRemovable = "Lit et enregistre des fichiers sur les disques amovibles."
    let usageNetwork = "Lit et enregistre des fichiers sur les disques réseau."
}
