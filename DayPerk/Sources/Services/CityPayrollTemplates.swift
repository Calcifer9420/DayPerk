import Foundation

struct CityPolicySource: Codable, Identifiable {
    var title: String
    var url: String
    var id: String {
        url
    }
}

struct CityPayrollTemplate: Codable, Identifiable {
    var id: String
    var name: String
    var period: String
    var values: [String: Double]
    var pending: String
    var note: String
    var sources: [CityPolicySource]

    func applying(to original: DayPerkConfiguration) -> DayPerkConfiguration {
        var c = original
        var p = c.payroll.policy
        if let v = values["pension"] {
            p.pensionRate = v / 100
        }
        if let v = values["medical"] {
            p.medicalRate = v / 100
        }
        if let v = values["unemployment"] {
            p.unemploymentRate = v / 100
        }
        if let v = values["socialMin"] {
            p.socialBaseMinimum = v
        }
        if let v = values["socialMax"] {
            p.socialBaseMaximum = v
        }
        if let v = values["medicalMin"] {
            p.medicalBaseMinimum = v
        }
        if let v = values["medicalMax"] {
            p.medicalBaseMaximum = v
        }
        if let v = values["unemploymentMin"] {
            p.unemploymentBaseMinimum = v
        }
        if let v = values["unemploymentMax"] {
            p.unemploymentBaseMaximum = v
        }
        if let v = values["medicalFixed"] {
            p.personalMedicalFixed = v
        }
        if let v = values["fundMin"] {
            p.housingBaseMinimum = v
        }
        if let v = values["fundMax"] {
            p.housingBaseMaximum = v
        }
        if let v = values["fundRate"] {
            c.payroll.housingFundRate = v / 100
        }
        if let v = values["employerFundRate"] {
            p.employerHousingFundRate = v / 100
        }
        p.supplementaryFundRate = (values["fundSupplemental"] ?? 0) / 100
        p.employerSupplementaryFundRate = (values["employerFundSupplemental"] ?? 0) / 100
        p.employerPensionRate = values["employerPension"].map { $0 / 100 }
        p.employerMedicalRate = values["employerMedical"].map { $0 / 100 }
        p.employerUnemploymentRate = values["employerUnemployment"].map { $0 / 100 }
        p.employerMaternityRate = values["employerMaternity"].map { $0 / 100 }
        p.medicalIncludesMaternity = values["medicalIncludesMaternity"] == 1
        p.employerInjuryRate = values["employerInjury"].map { $0 / 100 }
        p.cityTemplateID = id
        c.payroll.policy = p
        return c
    }
}

/// 企业职工可编辑默认方案；估算费率与一类工伤基准单独说明，不充当单位实际核定值。
enum CityPayrollTemplates {
    static let all: [CityPayrollTemplate] = PayrollCatalog.bundled.mainlandChinaCities
}
