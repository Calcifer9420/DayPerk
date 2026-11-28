import AppKit
import Foundation

enum PanelLayoutMode: Hashable { case locked, details }

/// 按用户填写的税后额外收入计入收益，公积金提取额同样由用户自行填写。
struct WithdrawableBenefit: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var monthlyAmount: Double = 0
    var includeInRate = true
    var showInEstimate = true
    var usesHousingFundAmount = false
    var displayName: String { usesHousingFundAmount && name.isEmpty ? L10n.text("ui.housing_fund.397c8572") : name }
    var isConfigured: Bool { !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && monthlyAmount > 0 }

    enum CodingKeys: String, CodingKey { case id, name, monthlyAmount, includeInRate, showInEstimate, usesHousingFundAmount }
    init(id: String = UUID().uuidString, name: String = "", monthlyAmount: Double = 0,
         includeInRate: Bool = true, showInEstimate: Bool = true, usesHousingFundAmount: Bool = false) {
        self.id = id; self.name = name; self.monthlyAmount = monthlyAmount
        self.includeInRate = includeInRate; self.showInEstimate = showInEstimate
        self.usesHousingFundAmount = usesHousingFundAmount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "legacy"
        name = try c.decode(String.self, forKey: .name)
        monthlyAmount = try c.decode(Double.self, forKey: .monthlyAmount)
        includeInRate = try c.decode(Bool.self, forKey: .includeInRate)
        showInEstimate = try c.decode(Bool.self, forKey: .showInEstimate)
        usesHousingFundAmount = try c.decodeIfPresent(Bool.self, forKey: .usesHousingFundAmount) ?? false
    }

    func validate() throws {
        guard monthlyAmount.isFinite, monthlyAmount >= 0, monthlyAmount <= 1_000_000_000,
              !id.isEmpty, id.count <= 100, name.count <= 80,
              monthlyAmount == 0 || usesHousingFundAmount || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DayPerkInputError(message: L10n.text("ui.enter_a_benefit_name_and_a_valid_no.cef26c0d"))
        }
    }

    static func validate(_ values: [Self], region: PayrollRegion) throws {
        guard values.count <= 50, Set(values.map(\.id)).count == values.count,
              values.filter(\.usesHousingFundAmount).count <= (region == .china ? 1 : 0) else {
            throw DayPerkInputError(message: L10n.text("benefits.invalid_list"))
        }
        for value in values { try value.validate() }
    }
}

extension DayPerkModel {
    func withdrawableBenefits(region: PayrollRegion, currency: String) -> [WithdrawableBenefit] {
        regional.withdrawableBenefits(region: region, currency: currency)
    }
    var withdrawableBenefits: [WithdrawableBenefit] { withdrawableBenefits(region: regional.region, currency: activeCurrencyCode) }
    var benefitForRate: Double {
        withdrawableBenefits.filter { $0.isConfigured && $0.includeInRate }.reduce(0) { $0 + $1.monthlyAmount }
    }
    var benefitForEstimate: Double {
        estimateBenefits.reduce(0) { $0 + $1.monthlyAmount }
    }
    var estimateBenefits: [WithdrawableBenefit] { withdrawableBenefits.filter { $0.isConfigured && $0.showInEstimate } }
    var takeHomeEstimateFormula: String {
        func money(_ amount: Double) -> String {
            WorkReportPresentation.money(currency.formatAmount(amount), showcase: privacy.isStatisticsShowcaseEnabled,
                unlocked: true, privacyEnabled: privacy.isPrivacyModeEnabled)
        }
        let net = breakdown.netMonthlyIncome
        guard benefitForEstimate > 0 else { return money(net) }
        let title = estimateBenefits.count == 1 ? estimateBenefits[0].displayName : L10n.text("benefits.title")
        return money(net) + " + " + title + " " + money(benefitForEstimate) + " = " + money(net + benefitForEstimate)
    }
    func chinaTrackingBasis(gross: Double, configuration: PayrollDeductionConfiguration) -> Double {
        let basis = PayrollCalculator.trackingBasis(gross: gross, configuration: configuration, includeHousingFund: false)
        let benefits = withdrawableBenefits(region: .china, currency: activeCurrencyCode)
        return basis.salary + basis.bonus + benefits.filter { $0.isConfigured && $0.includeInRate }.reduce(0) { $0 + $1.monthlyAmount }
    }
    func updateBenefitOptions(id: String, includeInRate: Bool? = nil, showInEstimate: Bool? = nil) {
        var values = withdrawableBenefits
        guard let i = values.firstIndex(where: { $0.id == id }) else { return }
        if let includeInRate { values[i].includeInRate = includeInRate }
        if let showInEstimate { values[i].showInEstimate = showInEstimate }
        do { try saveBenefits(values, region: regional.region, currency: activeCurrencyCode); actionError = nil }
        catch { actionError = error.localizedDescription }
    }
    var panelLayoutMode: PanelLayoutMode {
        access.isDataLocked ? .locked : .details
    }
    var preferredPanelHeight: CGFloat {
        panelContentHeights[panelLayoutMode] ?? (access.isDataLocked ? 560 : 636)
    }
    func recordPanelContentHeights(_ values: [PanelLayoutMode: CGFloat]) {
        var next = panelContentHeights
        for (mode, height) in values where height.isFinite && height >= 100 {
            next[mode] = ceil(height)
        }
        if next != panelContentHeights { panelContentHeights = next }
    }
    func updateBenefitOptions(includeInRate: Bool? = nil, showInEstimate: Bool? = nil) {
        guard let first = withdrawableBenefits.first else { return }
        updateBenefitOptions(id: first.id, includeInRate: includeInRate, showInEstimate: showInEstimate)
    }
}

extension RegionalPayEstimate {
    func monthlyTimeValueBasis(deduct: Bool, benefit: WithdrawableBenefit) -> Double {
        monthlyTimeValueBasis(deduct: deduct, benefits: [benefit])
    }
    func monthlyTimeValueBasis(deduct: Bool, benefits: [WithdrawableBenefit]) -> Double {
        (deduct ? cashNet : annualGross) / 12 + benefits.filter { $0.isConfigured && $0.includeInRate }.reduce(0) { $0 + $1.monthlyAmount }
    }
}
