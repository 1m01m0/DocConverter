import Foundation

public enum TextUtil {
    public static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x2E80...0x9FFF).contains(v) || (0xAC00...0xD7AF).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0xFF00...0xFFEF).contains(v) || (0x20000...0x2FA1F).contains(v) || (0x3000...0x303F).contains(v)
    }

    /// 合并两行文字：中日韩字符之间不加空格，西文之间加空格，行尾连字符直接拼接
    public static func joinLines(_ a: String, _ b: String) -> String {
        guard let la = a.last, let fb = b.first else { return a + b }
        if la == "-" , a.count > 1, let prev = a.dropLast().last, prev.isLetter, fb.isLowercase {
            return String(a.dropLast()) + b
        }
        if isCJK(la) || isCJK(fb) || la == " " || fb == " " { return a + b }
        return a + " " + b
    }

    static let radicalMap: [UInt32: Character] = [
        0x2EC5: "见", 0x2EC6: "角", 0x2EC8: "讠", 0x2EC9: "贝", 0x2ECB: "车", 0x2ECC: "辶", 0x2ED0: "钅", 0x2ED3: "长",
        0x2ED4: "门", 0x2ED9: "韦", 0x2EDA: "页", 0x2EDB: "风", 0x2EDC: "飞", 0x2EE0: "饣", 0x2EE2: "马", 0x2EE5: "鱼",
        0x2EE6: "鸟", 0x2EE7: "卤", 0x2EE8: "麦", 0x2EE9: "黄", 0x2EEA: "黾", 0x2EEC: "齐", 0x2EEE: "齿", 0x2EF0: "龙",
        0x2EF3: "龟", 0x2EB0: "纟", 0x2ED8: "青", 0x2EC4: "西", 0x2E9F: "母", 0x2EEB: "斉", 0x2EED: "歯", 0x2EEF: "竜", 0x2EF2: "亀",
    ]

    /// 把 PDF 中常见的康熙部首 / 部首补充字符（U+2F00–U+2FD5、U+2E80–U+2EF3）还原为常用汉字
    public static func normalizeCJKRadicals(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { (0x2E80...0x2FDF).contains($0.value) }) else { return s }
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if (0x2F00...0x2FDF).contains(u.value) {
                out.append(contentsOf: String(u).precomposedStringWithCompatibilityMapping.unicodeScalars)
            } else if let c = radicalMap[u.value] {
                out.append(contentsOf: c.unicodeScalars)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 文件名安全化
    public static func safeFileName(_ s: String, maxLength: Int = 80) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var r = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        if r.count > maxLength { r = String(r.prefix(maxLength)) }
        return r.isEmpty ? "untitled" : r
    }

    /// 估算显示宽度（中日韩字符算 2）
    public static func displayWidth(_ s: String) -> Int {
        s.reduce(0) { $0 + (isCJK($1) ? 2 : 1) }
    }

    public static func base64DataURI(_ img: ImageData) -> String {
        "data:\(img.mime);base64,\(img.data.base64EncodedString())"
    }

    /// 解析 data: URI
    public static func decodeDataURI(_ s: String) -> ImageData? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let meta = s[s.index(s.startIndex, offsetBy: 5)..<comma]
        let payload = String(s[s.index(after: comma)...])
        let mime = meta.split(separator: ";").first.map(String.init)
        if meta.contains("base64") {
            guard let d = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { return nil }
            return ImageData(data: d, mime: mime)
        }
        guard let d = payload.removingPercentEncoding?.data(using: .utf8) else { return nil }
        return ImageData(data: d, mime: mime)
    }

    /// 根据引用路径加载本地图片（相对 baseDir），支持 data URI
    public static func loadImage(src: String, baseDir: URL?, alt: String) -> ImageData? {
        if src.hasPrefix("data:") {
            var img = decodeDataURI(src); img?.alt = alt
            return img
        }
        if src.hasPrefix("http://") || src.hasPrefix("https://") { return nil }
        var path = src.removingPercentEncoding ?? src
        if path.hasPrefix("file://") { path = URL(string: src)?.path ?? path }
        let url: URL
        if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
        else if let b = baseDir { url = b.appendingPathComponent(path) }
        else { return nil }
        guard let d = try? Data(contentsOf: url) else { return nil }
        return ImageData(data: d, mime: ImageInfo.mime(forExtension: url.pathExtension), alt: alt)
    }

    /// 把块列表转成纯文本行（用于 CSV / XLSX 等纯数据格式的非表格部分）
    public static func plainLines(_ blocks: [Block]) -> [String] {
        var out: [String] = []
        for b in blocks {
            switch b {
            case .heading(_, let c), .paragraph(let c): out.append(c.plainText)
            case .list(let ordered, let start, let items):
                for (i, it) in items.enumerated() {
                    let lines = plainLines(it.blocks)
                    let marker = ordered ? "\(start + i). " : "• "
                    if let f = lines.first { out.append(marker + f) }
                    out.append(contentsOf: lines.dropFirst().map { "    " + $0 })
                }
            case .table(let t): out.append(contentsOf: t.rows.map { $0.map(\.text).joined(separator: "\t") })
            case .code(let text, _): out.append(contentsOf: text.components(separatedBy: "\n"))
            case .quote(let inner): out.append(contentsOf: plainLines(inner))
            case .image(let img): if !img.alt.isEmpty { out.append(L.imagePlaceholder(img.alt)) }
            case .horizontalRule, .pageBreak: break
            }
        }
        return out
    }
}
