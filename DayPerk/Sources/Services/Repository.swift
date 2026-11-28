// DayPerk，许可条款见仓库 LICENSE。
import Foundation

/// 保留既有键名前缀与编码方式，不迁移或删除用户历史配置。
final class UserDefaultsRepository<T: Codable> {
    private let keyPrefix: String
    init(keyPrefix: String) { self.keyPrefix = keyPrefix }

    func save(_ entity: T, key: String) throws {
        UserDataStore.shared.set(try JSONEncoder().encode(entity), forKey: keyPrefix + key)
    }

    func load(key: String) throws -> T? {
        guard let data = UserDataStore.shared.data(forKey: keyPrefix + key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

final class RepositoryManager {
    static let shared = RepositoryManager()
    let userProfileRepository = UserDefaultsRepository<SalaryProfile>(keyPrefix: "userProfile_")
    let workScheduleRepository = UserDefaultsRepository<ReferenceSchedule>(keyPrefix: "workSchedule_")
}
