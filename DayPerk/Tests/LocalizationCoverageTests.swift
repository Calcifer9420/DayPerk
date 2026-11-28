import Foundation
import Testing
@testable import DayPerk

struct LocalizationCoverageTests {
    private func resources(_ language: String) throws -> [String: String] {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let file = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
        return try #require(value as? [String: String])
    }

    @Test func everyLanguageHasTheSameRegisteredTextsAndFormatArguments() throws {
        let english = try resources("en")
        #expect(english.count >= 1000)
        let pattern = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?@"#)
        func placeholders(_ value: String) -> [String] {
            let range = NSRange(value.startIndex..., in: value)
            return pattern.matches(in: value, range: range).map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for language in AppLanguage.allCases where language != .system {
            let translated = try resources(language.rawValue)
            #expect(Set(translated.keys) == Set(english.keys))
            for (key, text) in translated {
                #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "空文本：\(language.rawValue) \(key)")
                #expect(placeholders(text) == placeholders(english[key] ?? ""), "占位符不同：\(language.rawValue) \(key)")
            }
        }
    }

    @Test func missingLanguageFallsBackToEnglishAndTemplatesPreserveUserText() {
        let localization = LocalizationManager.shared
        #expect(localization.string(for: "payroll.region.DE", language: "xx") == "Germany")
        #expect(localization.string(for: "工资与扣除", language: "zh-Hans") == "工资与扣除")
        #expect(localization.string(for: "北京", language: "zh-Hans") == "北京")
        #expect(localization.string(for: "month", language: "en") == "month")
        let custom = HelpFormulaRow(amount: "123", label: "내 마음대로 적은 이름", isUserProvidedLabel: true)
        #expect(custom.resolvedLabel(translate: { _ in "改写" }) == "내 마음대로 적은 이름")
        for language in AppLanguage.allCases.filter({ $0 != .system }).map(\.rawValue) {
            let format = localization.string(for: "duration.hours_minutes", language: language)
            let value = String(format: format, arguments: ["12", "34"])
            #expect(value.contains("12") && value.contains("34") && !value.contains("%@"))
            #expect(String(format: localization.string(for: "ui.1.aee4ea58", language: language), arguments: ["•••"]) == "•••/min")
        }
    }

    @Test func traditionalChineseAndLanguageHeadingsRespectTheSelectedLanguage() {
        let manager = LocalizationManager.shared
        for identifier in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh_Hant_HK"] {
            #expect(LocalizationManager.languageCode(for: identifier) == "zh-Hant")
        }
        for identifier in ["zh", "zh-CN", "zh-SG", "zh-Hans-HK"] {
            #expect(LocalizationManager.languageCode(for: identifier) == "zh-Hans")
        }
        #expect(LocalizationManager.languageCode(for: "fr-CA") == "fr")
        #expect(manager.languageHeading(for: "en") == "Language")
        #expect(manager.languageHeading(for: "zh-Hans") == "Language 语言")
        #expect(manager.languageHeading(for: "zh-Hant") == "Language 語言")
        #expect(manager.string(for: "leave.save_segment", language: "zh-Hant") == "儲存這一段")
        #expect(manager.string(for: "payroll.region.HK", language: "zh-Hant") == "中國香港")
    }

    @Test func hongKongAndMacauPresetAndHolidayTextsAreRegistered() throws {
        var keys = Set<String>()
        for region in [PayrollRegion.hongKong, .macau] {
            keys.insert("payroll.region." + region.rawValue)
            for policy in PayrollCatalog.bundled.policies(for: region) {
                keys.insert(policy.city)
                keys.formUnion(policy.assumptions + policy.sources.map(\.title) + policy.contributions.map(\.name) + Array(policy.parameters.keys))
            }
        }
        let calendar = RegionalHolidayCalendar(defaults: UserDefaults(suiteName: "language-hkmo-\(UUID())")!)
        for country in ["HK", "MO"] { keys.formUnion(calendar.days(country: country, subdivision: country).map(\.name)) }
        for language in AppLanguage.allCases where language != .system {
            let translations = try resources(language.rawValue)
            for key in keys { #expect(translations[key] != nil, "缺少翻译：\(language.rawValue) \(key)") }
        }
    }

    @Test func paydayFormattingUsesTheConfiguredTimeZone() {
        for identifier in ["America/Los_Angeles", "Pacific/Auckland"] {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: identifier)!
            let date = c.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 12))!
            #expect(L10n.payday(date, calendar: c).contains("30"))
        }
    }

    @Test func oversizedAmountIsMeasuredAtItsReadableFontSize() {
        #expect(OverflowAmount.width("¥9,999,999,999,999,999.99", size: 38, weight: .medium) > 300)
        #expect(OverflowAmount.width("•••", size: 38, weight: .medium) < 100)
        #expect(MarqueeOffset.scrolled(100, delta: -30, textWidth: 600, viewport: 300) == 130)
        #expect(MarqueeOffset.scrolled(100, delta: 300, textWidth: 600, viewport: 300) == 0)
        #expect(MarqueeOffset.scrolled(100, delta: -900, textWidth: 600, viewport: 300) == 300)
        #expect(MarqueeOffset.value(textWidth: 400, elapsed: 1) == 0)
        #expect(MarqueeOffset.value(textWidth: 400, elapsed: 2) > 0)
        #expect(abs(MarqueeOffset.value(textWidth: 400, elapsed: 1.2 + 432 / 28)) < 0.001)
        #expect(MarqueeOffset.value(textWidth: .infinity, elapsed: 2) == 0)
    }
}
