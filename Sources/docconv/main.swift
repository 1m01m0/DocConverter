import Foundation
import DocCore
import DocCoreMac

// docconv —— 文档格式互转命令行工具

var args = Array(CommandLine.arguments.dropFirst())

// 语言：--lang 优先，其次 LC_ALL / LC_MESSAGES / LANG，再次系统语言
Localizer.current = AppLanguage.fromEnvironment()
if let i = args.firstIndex(of: "--lang") {
    guard i + 1 < args.count else { print(L.cliUnknownLanguage("")); exit(1) }
    guard let lang = AppLanguage.match(args[i + 1]) else { print(L.cliUnknownLanguage(args[i + 1])); exit(1) }
    Localizer.current = lang
    args.removeSubrange(i...(i + 1))
}

// 打包脚本用：输出某种语言的 InfoPlist.strings
if args.first == "--infoplist-strings", args.count == 2, let lang = AppLanguage.match(args[1]) {
    let s = lang.strings
    func q(_ v: String) -> String { "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    print("CFBundleName = \(q(s.appName));")
    print("CFBundleDisplayName = \(q(s.appName));")
    for key in ["NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription"] {
        print("\(key) = \(q(s.usageFolders));")
    }
    print("NSRemovableVolumesUsageDescription = \(q(s.usageRemovable));")
    print("NSNetworkVolumesUsageDescription = \(q(s.usageNetwork));")
    exit(0)
}

let engine = ConversionEngine.shared
MacFormats.register(on: engine)

func usage(_ code: Int32 = 1) -> Never {
    let rows: [(String, String)] = [
        ("-t, --to <format>", L.cliTo),
        ("-o, --out <dir>", L.cliOut),
        ("--page <a4|letter|a3|a5>", L.cliPage),
        ("--landscape", L.cliLandscape),
        ("--font-size <pt>", L.cliFontSize),
        ("--margin <pt>", L.cliMargin),
        ("--pdf-mode <text|images>", L.cliPdfMode),
        ("--no-ocr", L.cliNoOCR),
        ("--split <1-6>", L.cliSplit),
        ("--notes", L.cliNotes),
        ("--embed-images", L.cliEmbedImages),
        ("--dpi <n>", L.cliDPI),
        ("--libreoffice", L.cliLibreOffice),
        ("--lang <code>", L.cliLang),
        ("--dump", L.cliDump),
        ("--verbose", L.cliVerbose),
        ("--formats", L.cliFormats),
        ("-h, --help", L.cliHelp),
    ]
    var out = L.cliUsage + "\n\n" + L.cliOptions + "\n"
    for (k, v) in rows { out += "  " + k.padding(toLength: 27, withPad: " ", startingAt: 0) + v + "\n" }
    out += "\n\(L.cliReadable): " + engine.inputFormats.map(\.rawValue).joined(separator: " ")
    out += "\n\(L.cliWritable): " + engine.outputFormats.map(\.rawValue).joined(separator: " ")
    print(out)
    exit(code)
}

var target: Format? = nil
var outDir: URL? = nil
var options = ConversionOptions()
var files: [URL] = []
var dump = false
var verbose = false

while !args.isEmpty {
    let a = args.removeFirst()
    func next() -> String { if args.isEmpty { usage() }; return args.removeFirst() }
    switch a {
    case "-t", "--to":
        let v = next()
        guard let f = Format(rawValue: v.lowercased()) ?? Format.from(extension: v) else { print(L.cliUnknownFormat(v)); exit(1) }
        target = f
    case "-o", "--out": outDir = URL(fileURLWithPath: next())
    case "--page": options.pageSize = PageSize(rawValue: next().lowercased()) ?? .a4
    case "--landscape": options.landscape = true
    case "--font-size": options.baseFontSize = Double(next()) ?? 11
    case "--margin": options.marginPt = Double(next()) ?? 56
    case "--pdf-mode": options.pdfReadMode = next() == "images" ? .pageImages : .text
    case "--no-ocr": options.ocrScannedPages = false
    case "--split": options.slideSplitLevel = min(6, max(1, Int(next()) ?? 2))
    case "--notes": options.includeSpeakerNotes = true
    case "--embed-images": options.embedImagesInMarkdown = true
    case "--dpi": options.imageDPI = min(1200, max(36, Double(next()) ?? 150))
    case "--libreoffice": options.useLibreOffice = true
    case "--dump": dump = true
    case "--verbose": verbose = true
    case "--formats":
        let r = L.cliReadMark, w = L.cliWriteMark
        let blank = String(repeating: " ", count: max(r.count, w.count))
        for f in Format.allCases {
            let rr = engine.canRead(f) ? r : blank
            let ww = engine.outputFormats.contains(f) ? w : blank
            print("\(rr) \(ww)  \(f.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(f.displayName)")
        }
        exit(0)
    case "-h", "--help": usage(0)
    default:
        if a.hasPrefix("-") && a.count > 1 && !FileManager.default.fileExists(atPath: a) {
            print(L.cliUnknownOption(a) + "\n")
            usage()
        }
        files.append(URL(fileURLWithPath: a))
    }
}

if files.isEmpty { usage() }

// PDFKit / CoreText 会向 stderr 打印大量调试信息，默认屏蔽（结果都输出到 stdout）
if !verbose {
    let devnull = open("/dev/null", O_WRONLY)
    if devnull >= 0 { dup2(devnull, STDERR_FILENO); close(devnull) }
}

if dump {
    for f in files {
        do { print(try engine.read(f, options: options)) } catch { print("✗ \(f.lastPathComponent): \(error.localizedDescription)") }
    }
    exit(0)
}

guard let target = target else { usage() }
var failures = 0
for f in files {
    let start = Date()
    do {
        let outs = try engine.convert(f, to: target, outputDirectory: outDir, options: options)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("✓ \(f.lastPathComponent) → \(outs.map(\.lastPathComponent).joined(separator: ", "))  (\(ms) ms)")
    } catch {
        failures += 1
        print("✗ \(f.lastPathComponent): \(error.localizedDescription)")
    }
}
exit(failures == 0 ? 0 : 2)
