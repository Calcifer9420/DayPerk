import Foundation

extension DayPerkModel {
    func resetDisplaySettings(completion: @escaping (Error?) -> Void) {
        access.resetDisplayPreferences(privacy: privacy, reset: {
            try self.appearance.resetToDefaults()
            self.currency.setDisplayPrecision(2)
            self.currency.setMenuBarPrecision(0)
            self.currency.setCurrency(self.usesChinaPayroll ? .cny : SupportedCurrency(rawValue: self.regional.selectedPolicy.currency) ?? .usd)
            LocalizationManager.shared.setLanguage(.english)
        }, completion: completion)
    }
}
