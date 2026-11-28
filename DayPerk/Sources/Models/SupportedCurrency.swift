import Foundation

enum SupportedCurrency: String, Codable, Identifiable, CaseIterable {
    case system, cny = "CNY", usd = "USD", eur = "EUR", gbp = "GBP"
    case sgd = "SGD", aud = "AUD", cad = "CAD", nzd = "NZD"
    case jpy = "JPY", krw = "KRW", hkd = "HKD", mop = "MOP", twd = "TWD"
    var id: String { rawValue }
    var currencyCode: String { self == .system ? (Locale.current.currency?.identifier ?? "CNY") : rawValue }
    var symbol: String {
        if self == .system { return MoneyDisplaySettings.shared.systemCurrency.symbol }
        return [Self.cny: "¥", .usd: "$", .eur: "€", .gbp: "£", .jpy: "¥", .krw: "₩", .sgd: "S$", .aud: "A$", .cad: "C$", .nzd: "NZ$", .hkd: "HK$", .mop: "MOP$", .twd: "NT$"][self]!
    }
    var displayName: String {
        guard self != .system else { return LocalizationManager.shared.localizedString(for: L10n.text("ui.system_default.7dfb2723")) }
        let name = LocalizationManager.shared.currentLocale.localizedString(forCurrencyCode: rawValue) ?? rawValue
        return "\(symbol) \(rawValue) (\(name))"
    }
}
