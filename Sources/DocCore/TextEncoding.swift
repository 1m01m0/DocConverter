import Foundation

// MARK: - 文本编码识别：BOM → UTF-8 → GB18030 → Big5 → Shift-JIS → Latin-1

public enum TextDecoder {
    public static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    public static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))

    public static func decode(_ data: Data) -> String {
        let b = [UInt8](data.prefix(4))
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? ""
        }
        // 无 BOM 的 UTF-16：大量 0 字节
        if data.count >= 4 {
            let sample = [UInt8](data.prefix(512))
            let evenZeros = stride(from: 0, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            let oddZeros = stride(from: 1, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            if oddZeros > sample.count / 4, evenZeros == 0, let s = String(data: data, encoding: .utf16LittleEndian) { return s }
            if evenZeros > sample.count / 4, oddZeros == 0, let s = String(data: data, encoding: .utf16BigEndian) { return s }
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = legacyCJK(data) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    /// 非 UTF-8 文本：先判断是不是西欧文字（Windows-1252），再在 Shift-JIS、Big5、GB18030 之间挑。
    /// GB18030 几乎能「解码」任何字节，所以不能简单地按顺序试，要先看特征：
    /// - Windows-1252：非 ASCII 字节稀疏、大多单独出现，解出来是带音调的拉丁字母或常见标点
    /// - Shift-JIS：日文几乎总有全角平假名/片假名；只有汉字时，首字节多在 0x81–0x9F，
    ///   而 GB2312 和 Big5 常用字的首字节都不低于 0xA1。GBK/Big5 字节按 Shift-JIS 解出来多是半角片假名
    /// - Big5：约四成汉字的第二字节在 0x40–0x7E；GB2312 常用字的第二字节都 ≥ 0xA1
    static func legacyCJK(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        if let w = westernText(bytes, data) { return w }

        var pairs = 0, lowTrail = 0, gbCommon = 0, lowLead = 0
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c >= 0x81, c <= 0xFE, i + 1 < bytes.count {
                let t = bytes[i + 1]
                pairs += 1
                if t >= 0x40, t <= 0x7E { lowTrail += 1 }
                if c >= 0xB0, c <= 0xF7, t >= 0xA1 { gbCommon += 1 }
                if c <= 0xA0 { lowLead += 1 }
                i += 2
            } else {
                i += 1
            }
        }
        if let sj = String(data: data, encoding: .shiftJIS) {
            var kana = 0, halfKana = 0, nonASCII = 0
            for u in sj.unicodeScalars where u.value > 0x7F {
                nonASCII += 1
                if (0x3040...0x30FF).contains(u.value) { kana += 1 }
                if (0xFF61...0xFF9F).contains(u.value) { halfKana += 1 }
            }
            if kana >= 2, kana * 10 >= nonASCII, halfKana * 2 < kana { return sj }
            if pairs > 0, lowLead * 10 >= pairs * 3, halfKana * 5 < max(1, nonASCII) { return sj }
        }
        if pairs > 0, gbCommon * 10 < pairs * 9, lowTrail * 100 >= pairs * 15, lowLead * 50 <= pairs,
           let b5 = String(data: data, encoding: big5) {
            return b5
        }
        return String(data: data, encoding: gb18030) ?? String(data: data, encoding: big5)
            ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// 西欧文字（德、法、西等）的 Windows-1252 文本
    static func westernText(_ bytes: [UInt8], _ data: Data) -> String? {
        var high = 0, runs = 0, runLen = 0
        for b in bytes {
            if b >= 0x80 { high += 1; runLen += 1 } else if runLen > 0 { runs += 1; runLen = 0 }
        }
        if runLen > 0 { runs += 1 }
        guard high > 0, high * 10 <= bytes.count * 3, high * 2 <= runs * 3 else { return nil }   // 稀疏、平均每段 ≤ 1.5 字节
        guard let s = String(data: data, encoding: .windowsCP1252) else { return nil }
        let allowed = Set("€‚„…†‡‘’“”•–—™«»°·¡¿ªº§©®²³µ½¼¾\u{00A0}".unicodeScalars.map(\.value))
        for u in s.unicodeScalars where u.value > 0x7F {
            let letter = (0xC0...0xFF).contains(u.value) && u.value != 0xD7 && u.value != 0xF7
            let extra = [0x152, 0x153, 0x160, 0x161, 0x17D, 0x17E, 0x178, 0x192].contains(u.value)
            if !letter && !extra && !allowed.contains(u.value) { return nil }
        }
        return s
    }

    public static func read(_ url: URL) throws -> String {
        decode(try Data(contentsOf: url))
    }

    /// 统一换行符
    public static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - 图片尺寸识别（PNG/JPEG/GIF/BMP/WebP）

public struct ImageInfo {
    public let mime: String
    public let width: Int
    public let height: Int

    public static func detect(_ data: Data) -> ImageInfo? {
        let b = [UInt8](data.prefix(64 * 1024))
        guard b.count >= 12 else { return nil }
        func be16(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i+1]) }
        func be32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i+1]) << 16 | Int(b[i+2]) << 8 | Int(b[i+3]) }
        func le16(_ i: Int) -> Int { Int(b[i]) | Int(b[i+1]) << 8 }
        func le32(_ i: Int) -> Int { le16(i) | le16(i+2) << 16 }

        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47, b.count >= 24 {
            return ImageInfo(mime: "image/png", width: be32(16), height: be32(20))
        }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 {
            return ImageInfo(mime: "image/gif", width: le16(6), height: le16(8))
        }
        if b[0] == 0x42, b[1] == 0x4D, b.count >= 26 {
            return ImageInfo(mime: "image/bmp", width: le32(18), height: abs(Int(Int32(truncatingIfNeeded: le32(22)))))
        }
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46, b.count >= 30, b[8] == 0x57, b[9] == 0x45 {
            // WebP VP8X / VP8 / VP8L
            let chunk = String(bytes: b[12..<16], encoding: .ascii) ?? ""
            if chunk == "VP8X" {
                let w = 1 + (Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16)
                let h = 1 + (Int(b[27]) | Int(b[28]) << 8 | Int(b[29]) << 16)
                return ImageInfo(mime: "image/webp", width: w, height: h)
            }
            if chunk == "VP8 " { return ImageInfo(mime: "image/webp", width: le16(26) & 0x3fff, height: le16(28) & 0x3fff) }
            if chunk == "VP8L" {
                let v = le32(21)
                return ImageInfo(mime: "image/webp", width: (v & 0x3fff) + 1, height: ((v >> 14) & 0x3fff) + 1)
            }
            return ImageInfo(mime: "image/webp", width: 0, height: 0)
        }
        if b[0] == 0xFF, b[1] == 0xD8 {
            var i = 2
            while i + 9 < b.count {
                guard b[i] == 0xFF else { i += 1; continue }
                let marker = b[i+1]
                if marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) { i += 2; continue }
                let len = be16(i + 2)
                if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                    return ImageInfo(mime: "image/jpeg", width: be16(i + 7), height: be16(i + 5))
                }
                i += 2 + len
            }
            return ImageInfo(mime: "image/jpeg", width: 0, height: 0)
        }
        if (b[0] == 0x49 && b[1] == 0x49) || (b[0] == 0x4D && b[1] == 0x4D) {
            return ImageInfo(mime: "image/tiff", width: 0, height: 0)
        }
        if let s = String(bytes: b.prefix(256), encoding: .utf8), s.contains("<svg") {
            return ImageInfo(mime: "image/svg+xml", width: 0, height: 0)
        }
        return nil
    }

    public static func mime(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "emf": return "image/x-emf"
        case "wmf": return "image/x-wmf"
        default: return nil
        }
    }
}
