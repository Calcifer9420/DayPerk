import Foundation

/// 只生成报表需要的 Open XML 和无压缩 ZIP，不引入第三方运行库。
enum ReportExcelExport {
    enum Cell {
        case text(String), number(Double, Int), formula(String, Double, Int)
    }
    static func data(report: WorkReport, currency: String, calendar: Calendar, locale: Locale) -> Data {
        let headers = ["ui.date.70d0c1b3", "export.currency", "report.expected_work_time", "ui.work_time.1a0937e5", "report.time_difference", "ui.expected_income.7b122310", "ui.time_value.a472b6c3", "report.money_difference", "leave.paid_hours", "leave.unpaid_hours", "leave.paid_days", "leave.unpaid_days"].map(L10n.text)
        let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .medium
        var rows: [[Cell]] = [headers.map(Cell.text)]
        // 和页面共用逐日汇总，未来日期不会在导出时提前变成收入或工时。
        let days = report.rows(byWeek: false, calendar: calendar)
        for day in days {
            let row = rows.count + 1
            rows.append([.text(day.days[0].id), .text(currency),
                .number(Double(day.expectedWorkSeconds) / 86400, 2), .number(Double(day.workSeconds) / 86400, 2),
                .formula("D\(row)-C\(row)", Double(day.timeDifferenceSeconds) / 86400, timeStyle(day.timeDifferenceSeconds)),
                .number(day.expectedIncome, 3), .number(day.earned, 3), .number(day.balance, balanceStyle(day.balance)),
                .number(Double(WorkDurationInput.wholeSeconds(day.paidLeaveSeconds)) / 86400, 2),
                .number(Double(WorkDurationInput.wholeSeconds(day.unpaidLeaveSeconds)) / 86400, 2),
                .number(day.paidLeaveDays, 3), .number(day.unpaidLeaveDays, 3)])
        }
        let last = rows.count
        rows.append([.text(L10n.text("export.total")), .text(currency)] + (2 ... 11).map { column in
            let value = [Double(report.expectedWorkSeconds) / 86400, Double(report.workSeconds) / 86400, Double(report.timeDifferenceSeconds) / 86400,
                report.expectedIncome, report.earned, report.balance,
                Double(days.reduce(0) { $0 + WorkDurationInput.wholeSeconds($1.paidLeaveSeconds) }) / 86400,
                Double(days.reduce(0) { $0 + WorkDurationInput.wholeSeconds($1.unpaidLeaveSeconds) }) / 86400,
                report.paidLeaveDays, report.unpaidLeaveDays][column - 2]
            let name = String(UnicodeScalar(65 + column)!)
            return .formula("SUM(\(name)2:\(name)\(last))", value, column == 4 ? timeStyle(report.timeDifferenceSeconds) : (column < 4 || column == 8 || column == 9) ? 2 : column == 7 ? balanceStyle(value) : 3)
        })
        let content = rows.enumerated().map { r, row in
            "<row r=\"\(r + 1)\" ht=\"\(r == 0 ? 44 : 26)\" customHeight=\"1\">" + row.enumerated().map { c, cell in
                let ref = String(UnicodeScalar(65 + c)!) + String(r + 1)
                switch cell {
                case let .text(value): return "<c r=\"\(ref)\" t=\"inlineStr\" s=\"\(r == 0 ? 1 : 0)\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
                case let .number(raw, style):
                    let value = style >= 3 && abs(raw) < 0.00000001 ? 0 : raw
                    return "<c r=\"\(ref)\" s=\"\(style)\"><v>\(value.isFinite ? value : 0)</v></c>"
                case let .formula(formula, raw, style):
                    let value = style >= 3 && abs(raw) < 0.00000001 ? 0 : raw
                    return "<c r=\"\(ref)\" s=\"\(style)\"><f>\(xml(formula))</f><v>\(value.isFinite ? value : 0)</v></c>"
                }
            }.joined() + "</row>"
        }.joined()
        let worksheet = """
        <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="22" customWidth="1"/><col min="2" max="2" width="16" customWidth="1"/><col min="3" max="12" width="25" customWidth="1"/></cols><sheetData>\(content)</sheetData><autoFilter ref="A1:L\(last)"/><headerFooter><oddHeader>\(xml("&L" + L10n.text("export.report_title") + "&R" + formatter.string(from: report.interval.start) + " – " + formatter.string(from: report.interval.end.addingTimeInterval(-1))))</oddHeader></headerFooter></worksheet>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="3"><numFmt numFmtId="164" formatCode="[hh]:mm:ss"/><numFmt numFmtId="166" formatCode="+[hh]:mm:ss;-[hh]:mm:ss;&quot;00:00:00&quot;"/><numFmt numFmtId="165" formatCode="[&gt;=0.005]#,##0.00;[&lt;=-0.005][Red]-#,##0.00;0.00"/></numFmts><fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF16843B"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FFCD3030"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF087B91"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="8"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="165" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="165" fontId="3" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="166" fontId="3" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="166" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """
        // 1904 日期系统支持负时长；日期列为文本，不受日期基点影响。
        return zip([
            ("[Content_Types].xml", "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>"),
            ("_rels/.rels", "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<?xml version=\"1.0\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><workbookPr date1904=\"1\"/><sheets><sheet name=\"\(xml(L10n.text("export.sheet")))\" sheetId=\"1\" r:id=\"rId1\"/></sheets><calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"),
            ("xl/worksheets/sheet1.xml", worksheet), ("xl/styles.xml", styles)
        ])
    }
    private static func balanceStyle(_ value: Double) -> Int { abs(value) < 0.005 ? 3 : value > 0 ? 4 : 5 }
    private static func timeStyle(_ seconds: Int) -> Int { seconds > 0 ? 6 : seconds < 0 ? 7 : 2 }
    static func xml(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || (32 ... 0xD7FF).contains($0.value) || (0xE000 ... 0xFFFD).contains($0.value) || (0x10000 ... 0x10FFFF).contains($0.value) })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    private static func zip(_ entries: [(String, String)]) -> Data {
        var archive = Data(), central = Data()
        for (name, text) in entries {
            let filename = Data(name.utf8), bytes = Data(text.utf8), offset = UInt32(archive.count)
            let crc = bytes.reduce(UInt32.max) { previous, byte in
                (0 ..< 8).reduce(previous ^ UInt32(byte)) { value, _ in (value >> 1) ^ (value & 1 == 0 ? 0 : 0xEDB88320) }
            } ^ UInt32.max
            archive.le(UInt32(0x04034B50)); archive.le(UInt16(20)); archive.le(UInt16(0x800)); archive.le(UInt16(0)); archive.le(UInt16(0)); archive.le(UInt16(33)); archive.le(crc); archive.le(UInt32(bytes.count)); archive.le(UInt32(bytes.count)); archive.le(UInt16(filename.count)); archive.le(UInt16(0)); archive.append(filename); archive.append(bytes)
            central.le(UInt32(0x02014B50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0x800)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(33)); central.le(crc); central.le(UInt32(bytes.count)); central.le(UInt32(bytes.count)); central.le(UInt16(filename.count)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(0)); central.le(offset); central.append(filename)
        }
        let offset = UInt32(archive.count); archive.append(central)
        archive.le(UInt32(0x06054B50)); archive.le(UInt16(0)); archive.le(UInt16(0)); archive.le(UInt16(entries.count)); archive.le(UInt16(entries.count)); archive.le(UInt32(central.count)); archive.le(offset); archive.le(UInt16(0))
        return archive
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } }
}
