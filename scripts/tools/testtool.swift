// 测试辅助工具（由 scripts/fulltest.sh 编译使用）
//   testtool pdfinfo <file.pdf>          输出：页数 宽 高 文字字符数
//   testtool encrypt <in.pdf> <out.pdf>  生成需要密码才能打开的 PDF
import Foundation
import PDFKit

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: testtool pdfinfo|encrypt ..."); exit(1) }
switch a[1] {
case "pdfinfo":
    guard let doc = PDFDocument(url: URL(fileURLWithPath: a[2])) else { print("ERROR"); exit(2) }
    if doc.isLocked { print("LOCKED"); exit(3) }
    let box = doc.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
    let chars = (doc.string ?? "").filter { !$0.isWhitespace }.count
    print("\(doc.pageCount) \(Int(box.width.rounded())) \(Int(box.height.rounded())) \(chars)")
case "encrypt":
    guard a.count == 4, let doc = PDFDocument(url: URL(fileURLWithPath: a[2])) else { exit(2) }
    let ok = doc.write(to: URL(fileURLWithPath: a[3]), withOptions: [
        PDFDocumentWriteOption.userPasswordOption: "secret",
        PDFDocumentWriteOption.ownerPasswordOption: "owner",
    ])
    exit(ok ? 0 : 2)
default:
    exit(1)
}
