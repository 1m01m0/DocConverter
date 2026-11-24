// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocConverter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DocCore", targets: ["DocCore"]),
        .executable(name: "docconv", targets: ["docconv"]),
        .executable(name: "DocConverterApp", targets: ["DocConverterApp"]),
    ],
    targets: [
        // 平台无关的核心：中间表示 + ZIP/XML + md/html/txt/csv/json/docx/pptx/xlsx/epub/tex
        .target(name: "DocCore", linkerSettings: [.linkedLibrary("z")]),
        // macOS 专用：PDF 读写、RTF/DOC/ODT、图片导出、LibreOffice 高保真引擎
        .target(name: "DocCoreMac", dependencies: ["DocCore"]),
        // 命令行工具
        .executableTarget(name: "docconv", dependencies: ["DocCore", "DocCoreMac"]),
        // SwiftUI 图形界面
        .executableTarget(name: "DocConverterApp", dependencies: ["DocCore", "DocCoreMac"]),
    ]
)
