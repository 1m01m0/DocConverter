// 生成应用图标（1024×1024 PNG）。用法：swift scripts/make_icon.swift 输出.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 背景：macOS 风格圆角方块 + 渐变
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(bgPath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.98, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.86, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: bgRect.minX, y: bgRect.maxY), end: CGPoint(x: bgRect.maxX, y: bgRect.minY), options: [])
ctx.restoreGState()

// 文档纸张
func page(_ rect: CGRect, fill: NSColor, fold: CGFloat, lines: NSColor?, label: String?, labelColor: NSColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
    p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(p); ctx.setFillColor(fill.cgColor); ctx.fillPath()
    ctx.restoreGState()
    // 折角
    let f = CGMutablePath()
    f.move(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
    f.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY - fold))
    f.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
    f.closeSubpath()
    ctx.addPath(f); ctx.setFillColor(NSColor(calibratedWhite: 0.82, alpha: 1).cgColor); ctx.fillPath()
    if let lc = lines {
        ctx.setFillColor(lc.cgColor)
        let lx = rect.minX + 44
        var ly = rect.maxY - fold - 50
        for i in 0..<5 {
            let w = (rect.width - 88) * (i == 4 ? 0.55 : (i % 2 == 0 ? 1 : 0.82))
            ctx.addPath(CGPath(roundedRect: CGRect(x: lx, y: ly, width: w, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
            ctx.fillPath()
            ly -= 46
        }
    }
    if let label = label {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 78, weight: .heavy), .foregroundColor: labelColor, .paragraphStyle: para]
        let s = NSAttributedString(string: label, attributes: attrs)
        s.draw(in: CGRect(x: rect.minX, y: rect.minY + 34, width: rect.width, height: 100))
    }
}

page(CGRect(x: 230, y: 330, width: 330, height: 430), fill: NSColor(calibratedWhite: 1, alpha: 0.92), fold: 80,
     lines: NSColor(calibratedRed: 0.62, green: 0.68, blue: 0.85, alpha: 1), label: "PDF", labelColor: NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.2, alpha: 1))
page(CGRect(x: 464, y: 250, width: 330, height: 430), fill: .white, fold: 80,
     lines: NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.82, alpha: 1), label: "DOC", labelColor: NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.78, alpha: 1))

// 转换箭头徽标
let badge = CGRect(x: 600, y: 196, width: 236, height: 236)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.12, alpha: 1).cgColor)
ctx.fillEllipse(in: badge)
ctx.restoreGState()
let cfg = NSImage.SymbolConfiguration(pointSize: 128, weight: .bold)
if let sym = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: CGRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon → \(out)")
