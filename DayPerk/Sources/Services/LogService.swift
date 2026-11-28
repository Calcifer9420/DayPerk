// DayPerk，许可条款见仓库 LICENSE。
import OSLog

enum LogService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.dayperk.mac", category: "lifecycle")
    static func info(_ message: String) {
        // 日志不记录薪资、文件路径或认证内容。
        logger.info("\(message, privacy: .public)")
    }
}
