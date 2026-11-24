import SwiftUI
import AppKit
import DocCore

typealias DocCoreFormat = DocCore.Format

final class AppDelegate: NSObject, NSApplicationDelegate {
    var language: LanguageSettings?
    var model: ConverterModel? {
        didSet {
            if let m = model, !pending.isEmpty { m.add(pending); pending = [] }
        }
    }
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let env = ProcessInfo.processInfo.environment
        if let path = env["DOCCONVERTER_SNAPSHOT"] { runSnapshot(to: path) }
        if let path = env["DOCCONVERTER_MENUDUMP"] {
            // 调试用：把菜单栏的全部菜单标题写到文本文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                func dump(_ menu: NSMenu, _ depth: Int) -> [String] {
                    menu.items.flatMap { item -> [String] in
                        guard !item.isSeparatorItem, !item.isHidden else { return [] }
                        let line = String(repeating: "  ", count: depth) + item.title
                        return [line] + (item.submenu.map { dump($0, depth + 1) } ?? [])
                    }
                }
                let text = NSApp.mainMenu.map { dump($0, 0) }?.joined(separator: "\n") ?? ""
                try? text.write(toFile: path, atomically: true, encoding: .utf8)
                if env["DOCCONVERTER_SNAPSHOT"] == nil { NSApp.terminate(nil) }
            }
        }
    }

    /// 调试用：DOCCONVERTER_SNAPSHOT=out.png DocConverter [文件…]
    /// 把窗口内容渲染为 PNG 后退出（不需要屏幕录制权限）。DOCCONVERTER_SNAPSHOT_CONVERT=1 时先执行转换。
    private func runSnapshot(to path: String) {
        let env = ProcessInfo.processInfo.environment
        let convert = env["DOCCONVERTER_SNAPSHOT_CONVERT"] == "1"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let files = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
            if !files.isEmpty { self.model?.add(files) }
            if let sz = env["DOCCONVERTER_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), sz.count == 2,
               let win = NSApp.windows.first(where: { $0.isVisible }) {
                win.setContentSize(NSSize(width: sz[0], height: sz[1]))
            }
            if let t = env["DOCCONVERTER_SNAPSHOT_TARGET"].flatMap({ DocCoreFormat(rawValue: $0) }) { self.model?.target = t }
            // 运行中切换语言（"system" 表示跟随系统）
            if let code = env["DOCCONVERTER_SNAPSHOT_SWITCH"] { self.language?.select(AppLanguage(rawValue: code)) }
            if let folder = env["DOCCONVERTER_SNAPSHOT_FOLDER"] {
                self.model?.customFolder = URL(fileURLWithPath: folder)
                self.model?.outputLocation = .custom
            }
            if convert { self.model?.start() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (convert ? 5 : 1.2)) {
                guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                      let view = win.contentView?.superview ?? win.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    /// 从 Finder「打开方式」或拖到程序坞图标打开的文件
    func application(_ application: NSApplication, open urls: [URL]) {
        if let m = model { m.add(urls) } else { pending.append(contentsOf: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DocConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = ConverterModel()
    @StateObject private var language = LanguageSettings()

    var body: some Scene {
        Window(language.language.strings.appName, id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(language)
                .id(language.language)   // 切换语言时整个界面重建，所有文字随之更新
                .onAppear { delegate.language = language; delegate.model = model }
        }
        .defaultSize(width: 920, height: 800)
        .commands {
            CommandGroup(replacing: .sidebar) { }   // 没有侧边栏，去掉系统默认的「Toggle Sidebar」
            CommandGroup(replacing: .newItem) {
                Button(L.addFilesMenu) { model.chooseFiles() }
                    .keyboardShortcut("o")
            }
            CommandMenu(L.convertMenu) {
                Button(L.startConvertMenu) { model.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canStart)
                Button(L.chooseSaveLocationMenu) { model.chooseFolder() }
                Divider()
                Button(L.clearListMenu) { model.clear() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.isConverting)
            }
        }
    }
}

DocConverterApp.main()
