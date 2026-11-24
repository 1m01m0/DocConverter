import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - 轻量 XML DOM（基于 XMLParser，可跨平台）
// 命名空间 URI 会被映射为固定前缀（w: a: p: r: x: ...），不依赖文档里实际使用的前缀。

public final class XNode {
    public let name: String                 // 规范化后的 "前缀:本地名"
    public var attributes: [String: String] // 键同样规范化，如 "r:id"、"val"
    public var children: [XNode] = []
    public var text: String = ""            // 仅文本节点使用
    public weak var parent: XNode?
    public let isText: Bool

    init(name: String, attributes: [String: String] = [:], isText: Bool = false) {
        self.name = name; self.attributes = attributes; self.isText = isText
    }

    public var localName: String {
        if let i = name.lastIndex(of: ":") { return String(name[name.index(after: i)...]) }
        return name
    }

    public var elements: [XNode] { children.filter { !$0.isText } }

    public func child(_ n: String) -> XNode? { children.first { !$0.isText && $0.name == n } }
    public func children(_ n: String) -> [XNode] { children.filter { !$0.isText && $0.name == n } }

    /// 深度优先查找所有匹配节点
    public func descendants(_ n: String) -> [XNode] {
        var out: [XNode] = []
        func walk(_ x: XNode) {
            for c in x.children where !c.isText {
                if c.name == n { out.append(c) }
                walk(c)
            }
        }
        walk(self)
        return out
    }

    public func first(_ n: String) -> XNode? {
        for c in children where !c.isText {
            if c.name == n { return c }
            if let f = c.first(n) { return f }
        }
        return nil
    }

    /// 路径查找，如 path("w:pPr", "w:pStyle")
    public func path(_ names: String...) -> XNode? {
        var cur: XNode? = self
        for n in names { cur = cur?.child(n) }
        return cur
    }

    public subscript(attr: String) -> String? { attributes[attr] }

    /// 所有文本（递归）
    public var textContent: String {
        if isText { return text }
        return children.map(\.textContent).joined()
    }
}

public enum XML {
    static let nsMap: [String: String] = [
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main": "w",
        "http://schemas.openxmlformats.org/drawingml/2006/main": "a",
        "http://schemas.openxmlformats.org/presentationml/2006/main": "p",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships": "r",
        "http://schemas.openxmlformats.org/package/2006/relationships": "rel",
        "http://schemas.openxmlformats.org/spreadsheetml/2006/main": "x",
        "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing": "wp",
        "http://schemas.openxmlformats.org/drawingml/2006/picture": "pic",
        "http://schemas.openxmlformats.org/markup-compatibility/2006": "mc",
        "http://schemas.microsoft.com/office/word/2010/wordml": "w14",
        "http://schemas.openxmlformats.org/officeDocument/2006/math": "m",
        "urn:schemas-microsoft-com:vml": "v",
        "http://www.w3.org/1999/xhtml": "h",
        "http://www.idpf.org/2007/opf": "opf",
        "http://purl.org/dc/elements/1.1/": "dc",
        "urn:oasis:names:tc:opendocument:xmlns:container": "ocf",
        "http://www.w3.org/XML/1998/namespace": "xml",
        "http://purl.oclc.org/ooxml/wordprocessingml/main": "w",
        "http://purl.oclc.org/ooxml/drawingml/main": "a",
        "http://purl.oclc.org/ooxml/presentationml/main": "p",
        "http://purl.oclc.org/ooxml/spreadsheetml/main": "x",
        "http://purl.oclc.org/ooxml/officeDocument/relationships": "r",
    ]

    public static func parse(_ data: Data) -> XNode? {
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.root.elements.first
    }

    public static func parse(_ string: String) -> XNode? { parse(Data(string.utf8)) }

    final class Builder: NSObject, XMLParserDelegate {
        let root = XNode(name: "#root")
        var stack: [XNode] = []
        override init() { super.init(); stack = [root] }

        func qualify(_ local: String, _ uri: String?) -> String {
            guard let uri = uri, !uri.isEmpty else { return local }
            if let p = XML.nsMap[uri] { return "\(p):\(local)" }
            return local
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            var attrs: [String: String] = [:]
            for (k, v) in attributeDict {
                // XMLParser 不会给属性做命名空间解析，这里按常见前缀做映射
                if let i = k.firstIndex(of: ":") {
                    let prefix = String(k[..<i]), local = String(k[k.index(after: i)...])
                    switch prefix {
                    case "r": attrs["r:\(local)"] = v
                    case "xml": attrs["xml:\(local)"] = v
                    case "xmlns": continue
                    default: attrs[local] = attrs[local] ?? v; attrs[k] = v
                    }
                } else if k != "xmlns" {
                    attrs[k] = v
                }
            }
            let node = XNode(name: qualify(elementName, namespaceURI), attributes: attrs)
            node.parent = stack.last
            stack.last?.children.append(node)
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if stack.count > 1 { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            appendText(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            appendText(String(decoding: CDATABlock, as: UTF8.self))
        }

        func appendText(_ s: String) {
            guard let cur = stack.last else { return }
            if let last = cur.children.last, last.isText {
                last.text += s
            } else {
                let t = XNode(name: "#text", isText: true)
                t.text = s
                t.parent = cur
                cur.children.append(t)
            }
        }
    }

    // MARK: 转义

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // 去掉 XML 1.0 不允许的控制字符
                let v = ch.value
                if v < 0x20 && v != 0x9 && v != 0xA && v != 0xD { continue }
                if v == 0xFFFE || v == 0xFFFF { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}

// MARK: - OOXML 关系文件

public struct Relationships {
    public var targets: [String: String] = [:]   // rId -> 绝对包内路径（或外部 URL）
    public var types: [String: String] = [:]
    public var external: Set<String> = []

    public init() {}

    /// partPath 例如 "word/document.xml"，对应 "word/_rels/document.xml.rels"
    public init(zip: ZipArchive, partPath: String) {
        let dir = (partPath as NSString).deletingLastPathComponent
        let file = (partPath as NSString).lastPathComponent
        let relsPath = (dir.isEmpty ? "" : dir + "/") + "_rels/" + file + ".rels"
        guard let d = zip.read(relsPath), let root = XML.parse(d) else { return }
        for r in root.elements where r.localName == "Relationship" {
            guard let id = r["Id"], let target = r["Target"] else { continue }
            types[id] = r["Type"] ?? ""
            if r["TargetMode"] == "External" {
                targets[id] = target
                external.insert(id)
            } else {
                targets[id] = Relationships.resolve(base: dir, target: target)
            }
        }
    }

    public static func resolve(base: String, target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in target.split(separator: "/") {
            if comp == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if comp != "." { parts.append(String(comp)) }
        }
        return parts.joined(separator: "/")
    }

    public func first(typeSuffix: String) -> String? {
        types.first { $0.value.hasSuffix(typeSuffix) }.flatMap { targets[$0.key] }
    }
}
