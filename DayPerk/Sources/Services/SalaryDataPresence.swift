import Foundation

/// 默认外观、公共政策和零工时占位不属于待保护的个人记录。
enum SalaryDataPresence {
    static func requiresProtection(defaults: any UserDataPreferences = UserDataStore.shared) -> Bool {
        let amountKeys = ["dayperkBaseSalary", "payrollAnnualBonusBase", "payrollContributionBase", "payrollHousingFundBase", "payrollMonthlySpecialAdditionalDeduction"]
        if amountKeys.contains(where: { defaults.double(forKey: $0) != 0 }) { return true }
        if contains("userProfile_current", SalaryProfile.self, defaults, matching: {
            $0.monthlySalary != 0 || (!$0.name.isEmpty && $0.name != "User")
        }) { return true }
        if contains("dayperkRegionalPayInput", RegionalPayInput.self, defaults, matching: { $0 != RegionalPayInput() }) { return true }
        if contains("manualWorkTrackingV1", WorkTrackingState.self, defaults, matching: { state in
            state.isWorking || state.activeWorkday != nil || state.days.contains { day in
                day.clockedInAt != nil || [day.seconds, day.overtimeSeconds, day.earned,
                    day.manualAdjustment ?? 0, day.ratePerSecond ?? 0, day.expectedIncome ?? 0,
                    day.grossRatePerSecond ?? 0, day.registeredDailyGross ?? 0].contains { $0 != 0 }
            }
        }) { return true }
        if contains("payrollIncomeRecords", [PayrollIncomeRecord].self, defaults, matching: { !$0.isEmpty }) { return true }
        if contains("dayperkInternationalIncomeRecords", [RegionalIncomeRecord].self, defaults, matching: { !$0.isEmpty }) { return true }
        if contains(WorkStatusController.storageKey, WorkStatusData.self, defaults, matching: { !$0.segments.isEmpty }) { return true }
        if contains(LeaveLedger.storageKey, [String: LeaveDay].self, defaults, matching: { $0.values.contains { !$0.isEmpty } }) { return true }
        if contains(LeaveRequests.storageKey, [LeaveRequest].self, defaults, matching: { !$0.isEmpty }) { return true }
        if contains("dayperkOvertimeDates", [String: Double].self, defaults, matching: { !$0.isEmpty }) { return true }
        if contains("dayperkWithdrawableBenefitsV2", [String: [WithdrawableBenefit]].self, defaults, matching: {
            $0.values.joined().contains { $0.monthlyAmount != 0 || !$0.name.isEmpty }
        }) { return true }
        return contains("dayperkWithdrawableBenefits", [String: WithdrawableBenefit].self, defaults) {
            $0.values.contains { $0.monthlyAmount != 0 || !$0.name.isEmpty }
        }
    }

    private static func contains<T: Decodable>(_ key: String, _ type: T.Type, _ defaults: any UserDataPreferences, matching predicate: (T) -> Bool) -> Bool {
        guard let stored = defaults.object(forKey: key) else { return false }
        // 有存档但不能读取时保留保护，不能把损坏的个人存档当作首次安装。
        guard let data = stored as? Data, let value = try? JSONDecoder().decode(type, from: data) else { return true }
        return predicate(value)
    }
}
