import Combine
import Foundation

/// 货币只影响显示；税务计算继续按对应规则使用的币种执行。
final class MoneyDisplaySettings: ObservableObject {
    static let shared = MoneyDisplaySettings()
    @Published private(set) var currentCurrency: SupportedCurrency
    @Published private(set) var displayDecimalPlaces: Int
    @Published private(set) var menuBarDecimalPlaces: Int

    var systemCurrency: SupportedCurrency { SupportedCurrency(rawValue: Locale.current.currency?.identifier ?? "CNY") ?? .cny }
    var currencySymbol: String { (currentCurrency == .system ? systemCurrency : currentCurrency).symbol }

    private init() {
        let defaults = UserDataStore.shared
        currentCurrency = SupportedCurrency(rawValue: defaults.string(forKey: "appCurrency") ?? "system") ?? .system
        displayDecimalPlaces = min(2, max(0, defaults.object(forKey: "amountDecimalPlaces") as? Int ?? 2))
        menuBarDecimalPlaces = min(2, max(0, defaults.integer(forKey: "menuBarDecimalPlaces")))
    }
    func reloadFromStorage() {
        let value = MoneyDisplaySettings()
        currentCurrency = value.currentCurrency; displayDecimalPlaces = value.displayDecimalPlaces; menuBarDecimalPlaces = value.menuBarDecimalPlaces
    }
    func setCurrency(_ currency: SupportedCurrency) {
        currentCurrency = currency
        UserDataStore.shared.set(currency.rawValue, forKey: "appCurrency")
    }
    func setDisplayPrecision(_ value: Int) {
        displayDecimalPlaces = min(2, max(0, value))
        UserDataStore.shared.set(displayDecimalPlaces, forKey: "amountDecimalPlaces")
    }
    func setMenuBarPrecision(_ value: Int) {
        menuBarDecimalPlaces = min(2, max(0, value))
        UserDataStore.shared.set(menuBarDecimalPlaces, forKey: "menuBarDecimalPlaces")
    }

    /// 仅消除显示精度下的正负零，非零值保留原始精度供后续计算。
    static func normalizedForDisplay(_ amount: Double, decimalPlaces: Int) -> Double {
        guard amount.isFinite else { return 0 }
        let scale = pow(10.0, Double(min(2, max(0, decimalPlaces))))
        return (amount * scale).rounded(.toNearestOrEven) == 0 ? 0 : amount
    }

    func formatAmount(_ amount: Double, currencyCode: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = displayDecimalPlaces
        formatter.maximumFractionDigits = displayDecimalPlaces
        let value = Self.normalizedForDisplay(amount, decimalPlaces: displayDecimalPlaces)
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        let symbol = currencyCode.flatMap(SupportedCurrency.init(rawValue:))?.symbol ?? currencySymbol
        return symbol + number
    }
}
