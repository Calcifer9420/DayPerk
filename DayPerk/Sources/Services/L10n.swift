import Foundation

/// 每种语言只读取一份 Localizable.strings；动态值通过占位符注入，不做文案片段替换。
enum L10n {
    static func text(_ key: String) -> String { LocalizationManager.shared.localizedString(for: key) }

    static func payday(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d EEE")
        return formatter.string(from: date)
    }

    static func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), locale: LocalizationManager.shared.currentLocale, arguments: values)
    }
}

enum LocalizedNumberInput {
    static func value(_ text: String, locale: Locale) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let escaped = NSRegularExpression.escapedPattern(for: separator)
        guard text.range(of: "^[+-]?(?:[0-9]+(?:" + escaped + "[0-9]+)?|" + escaped + "[0-9]+)$", options: .regularExpression) != nil,
              let value = Double(text.replacingOccurrences(of: separator, with: ".")), value.isFinite else { return nil }
        return value
    }
}
