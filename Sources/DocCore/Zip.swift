import Foundation
import zlib

// MARK: - 最小 ZIP 实现（读取 + 写入），用于 OOXML / EPUB 容器
// 读取时以中央目录为准（本地头在设置了 bit 3 时大小字段为 0）。

public struct ZipArchive {
    public struct Entry {
        public let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    public let data: Data
    public private(set) var entries: [String: Entry] = [:]
    public private(set) var orderedNames: [String] = []

    public init(data: Data) throws {
        self.data = data
        try parseCentralDirectory()
    }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    private mutating func parseCentralDirectory() throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ConversionError.invalidFile(L.notZip) }
        // 从尾部查找 End Of Central Directory (0x06054b50)
        var eocd = -1
        let minPos = max(0, bytes.count - 65557)
        var i = bytes.count - 22
        while i >= minPos {
            if bytes[i] == 0x50 && bytes[i+1] == 0x4b && bytes[i+2] == 0x05 && bytes[i+3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ConversionError.invalidFile(L.zipDirectoryMissing) }
        func u16(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p+1]) << 8 }
        func u32(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p+1]) << 8 | Int(bytes[p+2]) << 16 | Int(bytes[p+3]) << 24 }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { break }
            let flags = u16(p + 8)
            let method = UInt16(u16(p + 10))
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let offset = u32(p + 42)
            let nameBytes = Array(bytes[(p + 46)..<min(bytes.count, p + 46 + nlen)])
            let name: String
            if flags & 0x800 != 0 {
                name = String(decoding: nameBytes, as: UTF8.self)
            } else {
                name = String(bytes: nameBytes, encoding: .utf8)
                    ?? String(bytes: nameBytes, encoding: TextDecoder.gb18030)
                    ?? String(decoding: nameBytes, as: UTF8.self)
            }
            let e = Entry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, localHeaderOffset: offset)
            entries[name] = e
            orderedNames.append(name)
            p += 46 + nlen + elen + clen
        }
    }

    public func contains(_ name: String) -> Bool { entries[name] != nil }

    public func read(_ name: String) -> Data? {
        let key = name.hasPrefix("/") ? String(name.dropFirst()) : name
        guard let e = entries[key] ?? entries.first(where: { $0.key.lowercased() == key.lowercased() })?.value else { return nil }
        let p = e.localHeaderOffset
        guard p + 30 <= data.count else { return nil }
        let base = data.startIndex
        let nlen = Int(data[base + p + 26]) | Int(data[base + p + 27]) << 8
        let elen = Int(data[base + p + 28]) | Int(data[base + p + 29]) << 8
        let start = p + 30 + nlen + elen
        guard start + e.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: (base + start)..<(base + start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return Deflate.inflate(raw, expectedSize: e.uncompressedSize)
        default: return nil
        }
    }

    public func readString(_ name: String) -> String? {
        guard let d = read(name) else { return nil }
        return String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
    }
}

public final class ZipWriter {
    private var out = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public func add(_ name: String, _ data: Data, compress: Bool = true) {
        let nameData = Data(name.utf8)
        let crc = data.withUnsafeBytes { buf -> UInt32 in
            UInt32(crc32(0, buf.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
        }
        var payload = data
        var method: UInt16 = 0
        if compress, data.count > 64, let d = Deflate.deflate(data), d.count < data.count {
            payload = d; method = 8
        }
        let offset = UInt32(out.count)
        // 固定的 DOS 时间：2024-01-01 00:00
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = UInt16((2024 - 1980) << 9 | 1 << 5 | 1)

        var local = Data()
        local.le32(0x04034b50); local.le16(20); local.le16(0x0800); local.le16(method)
        local.le16(dosTime); local.le16(dosDate); local.le32(crc)
        local.le32(UInt32(payload.count)); local.le32(UInt32(data.count))
        local.le16(UInt16(nameData.count)); local.le16(0)
        out.append(local); out.append(nameData); out.append(payload)

        var c = Data()
        c.le32(0x02014b50); c.le16(20); c.le16(20); c.le16(0x0800); c.le16(method)
        c.le16(dosTime); c.le16(dosDate); c.le32(crc)
        c.le32(UInt32(payload.count)); c.le32(UInt32(data.count))
        c.le16(UInt16(nameData.count)); c.le16(0); c.le16(0); c.le16(0); c.le16(0)
        c.le32(0); c.le32(offset)
        central.append(c); central.append(nameData)
        count += 1
    }

    public func add(_ name: String, _ text: String, compress: Bool = true) {
        add(name, Data(text.utf8), compress: compress)
    }

    public func finish() -> Data {
        var result = out
        let cdOffset = UInt32(result.count)
        result.append(central)
        var e = Data()
        e.le32(0x06054b50); e.le16(0); e.le16(0)
        e.le16(UInt16(count)); e.le16(UInt16(count))
        e.le32(UInt32(central.count)); e.le32(cdOffset); e.le16(0)
        result.append(e)
        return result
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xff)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xff)) } }
}

// MARK: - zlib 原始 DEFLATE

enum Deflate {
    static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        if input.isEmpty { return Data() }
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(expectedSize, 1024))
        var status: Int32 = Z_OK
        let inCopy = [UInt8](input)
        inCopy.withUnsafeBufferPointer { inBuf in
            stream.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress!)
            stream.avail_in = uInt(inBuf.count)
            repeat {
                if Int(stream.total_out) >= output.count { output.count *= 2 }
                let written = Int(stream.total_out)
                status = output.withUnsafeMutableBytes { outBuf -> Int32 in
                    stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress! + written
                    stream.avail_out = uInt(outBuf.count - written)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
            } while status == Z_OK
        }
        guard status == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }

    static func deflate(_ input: Data) -> Data? {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        let bound = Int(deflateBound(&stream, uLong(input.count))) + 64
        var output = Data(count: bound)
        let inCopy = [UInt8](input)
        let status: Int32 = inCopy.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                stream.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress!)
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(outBuf.count)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }
}
