import SwiftUI
import DocCore

/// 界面语言设置。
/// 选择保存在本 App 的 AppleLanguages 里——与「系统设置 → 通用 → 语言与地区 → App」使用同一个键，
/// 所以两边改动互相可见；系统提供的菜单（编辑、窗口、退出…）也在下次启动时随之切换。
final class LanguageSettings: ObservableObject {
    /// nil 表示跟随系统
    @Published private(set) var choice: AppLanguage?
    @Published private(set) var language: AppLanguage

    private static var domain: String { Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName }

    init() {
        let stored = UserDefaults.standard.persistentDomain(forName: Self.domain)?["AppleLanguages"] as? [String]
        let explicit = stored?.first.flatMap(AppLanguage.match)
        choice = explicit
        // 未单独设置时用 Locale.preferredLanguages（它也会读取启动参数 -AppleLanguages）
        language = explicit ?? AppLanguage.preferred(from: Locale.preferredLanguages)
        Localizer.current = language
    }

    /// 系统全局的首选语言（不受本 App 单独设置的影响）
    var systemLanguage: AppLanguage {
        let global = CFPreferencesCopyValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication,
                                            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        return AppLanguage.preferred(from: global ?? Locale.preferredLanguages)
    }

    func select(_ newChoice: AppLanguage?) {
        let defaults = UserDefaults.standard
        if let l = newChoice {
            defaults.set([l.rawValue], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        choice = newChoice
        language = newChoice ?? systemLanguage
        Localizer.current = language
    }
}

/// 工具栏上的语言菜单
struct LanguageMenu: View {
    @EnvironmentObject var settings: LanguageSettings

    private var selection: Binding<String> {
        Binding(get: { settings.choice?.rawValue ?? "system" },
                set: { settings.select(AppLanguage(rawValue: $0)) })
    }

    var body: some View {
        Menu {
            Picker(L.language, selection: selection) {
                Text(L.followSystem(settings.systemLanguage.nativeName)).tag("system")
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Text(L.relaunchNote)
        } label: {
            Label(settings.language.nativeName, systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .help(L.language)
    }
}
