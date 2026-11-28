import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", chinese = "zh-Hans", traditionalChinese = "zh-Hant", japanese = "ja", korean = "ko", french = "fr", german = "de"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .chinese: return L10n.text("ui.message.9937e365")
        case .traditionalChinese: return L10n.text("language.zh_Hant")
        case .english: return L10n.text("ui.english.ba118bf7")
        case .japanese: return L10n.text("ui.message.77710aed")
        case .korean: return L10n.text("ui.message.ea325228")
        case .french: return L10n.text("language.fr")
        case .german: return L10n.text("language.de")
        case .system: return LocalizationManager.shared.localizedString(for: L10n.text("ui.system_default.8b8d99d0"))
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var currentLocale: Locale

    var systemLanguageCode: String {
        Self.languageCode(for: Locale.preferredLanguages.first ?? "en")
    }
    static func languageCode(for identifier: String) -> String {
        let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        if parts.first == "zh" {
            if parts.contains("hant") { return "zh-Hant" }
            if parts.contains("hans") { return "zh-Hans" }
            return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
        }
        return ["ja", "ko", "fr", "de"].first { $0 == parts.first } ?? "en"
    }
    var languageHeading: String { languageHeading(for: effectiveLanguageCode) }
    func languageHeading(for language: String) -> String {
        let english = string(for: "ui.language.9f6fee1a", language: "en")
        let local = string(for: "ui.language.9f6fee1a", language: language)
        return local.caseInsensitiveCompare(english) == .orderedSame ? english : english + " " + local
    }
    var effectiveLanguageCode: String { currentLanguage == .system ? systemLanguageCode : currentLanguage.rawValue }

    private init() {
        currentLanguage = AppLanguage(rawValue: UserDataStore.shared.string(forKey: "appLanguage") ?? "en") ?? .english
        currentLocale = .current
        currentLocale = Locale(identifier: effectiveLanguageCode)
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        currentLocale = Locale(identifier: effectiveLanguageCode)
        UserDataStore.shared.set(language.rawValue, forKey: "appLanguage")
    }

    func localizedString(for key: String, comment: String = "") -> String {
        string(for: key, language: effectiveLanguageCode)
    }

    func string(for key: String, language: String) -> String {
        for code in [language, "en"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { continue }
            let missing = "\u{001F}dayperk-missing:" + key
            let result = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
            if result != missing { return result }
        }
        return key
    }
}
