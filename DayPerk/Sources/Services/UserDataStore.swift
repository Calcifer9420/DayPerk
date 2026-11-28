import Foundation

protocol UserDataPreferences: AnyObject {
    func object(forKey: String) -> Any?
    func set(_ value: Any?, forKey: String)
    func removeObject(forKey: String)
    func dictionaryRepresentation() -> [String: Any]
    func persistentDomain(forName: String) -> [String: Any]?
    func setPersistentDomain(_ domain: [String: Any], forName: String)
    @discardableResult func synchronize() -> Bool
}

extension UserDefaults: UserDataPreferences {}

extension UserDataPreferences {
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }

    func persist(_ changes: [String: Any]) throws {
        if let store = self as? UserDataStore {
            try store.merge(changes)
        } else {
            let previous = dictionaryRepresentation()
            for (key, value) in changes { set(value, forKey: key) }
            guard synchronize() else {
                for key in changes.keys { set(previous[key], forKey: key) }
                _ = synchronize()
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }
}

/// 配置、账本与缓存共用独立目录；各应用标识隔离，旧偏好只复制一次且保留原件。
final class UserDataStore: UserDataPreferences, @unchecked Sendable {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DayPerk/UserData", isDirectory: true)
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.dayperk.mac", isDirectory: true)
    static let shared = UserDataStore(directory: directory, legacy: UserDefaults.standard)

    let directory: URL
    private let file: URL
    private var values: [String: Any] = [:]
    private let lock = NSRecursiveLock()
    private(set) var readError: Error?
    private(set) var writeError: Error?

    init(directory: URL, legacy: UserDefaults? = nil) {
        self.directory = directory
        file = directory.appendingPathComponent("settings.plist")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                guard let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else {
                    throw CocoaError(.propertyListReadCorrupt)
                }
                values = saved
            } else {
                values = legacy?.dictionaryRepresentation().filter { AppDataBackup.keys.contains($0.key) } ?? [:]
                let oldImage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("DayPerk/Appearance/background.png")
                let image = directory.appendingPathComponent("Appearance/background.png")
                if legacy != nil, FileManager.default.fileExists(atPath: oldImage.path), !FileManager.default.fileExists(atPath: image.path) {
                    try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: oldImage, to: image)
                }
                try flush()
            }
        } catch { readError = error }
    }

    func object(forKey key: String) -> Any? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func dictionaryRepresentation() -> [String: Any] { lock.lock(); defer { lock.unlock() }; return values }
    func persistentDomain(forName: String) -> [String: Any]? { dictionaryRepresentation() }
    func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
        _ = synchronize()
    }
    func removeObject(forKey key: String) { set(nil, forKey: key) }
    func setPersistentDomain(_ domain: [String: Any], forName: String) {
        lock.lock(); defer { lock.unlock() }
        values = domain
        _ = synchronize()
    }
    func replace(with replacement: [String: Any]) throws {
        lock.lock(); defer { lock.unlock() }
        let previous = values
        values = replacement
        do { try flush(); writeError = nil }
        catch { values = previous; throw error }
    }
    func merge(_ changes: [String: Any]) throws {
        lock.lock(); defer { lock.unlock() }
        let previous = values
        values.merge(changes, uniquingKeysWith: { _, new in new })
        do { try flush(); writeError = nil }
        catch { values = previous; throw error }
    }
    @discardableResult func synchronize() -> Bool {
        do { try flush(); writeError = nil; return true }
        catch {
            let firstFailure = writeError == nil
            writeError = error
            if firstFailure {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .dayPerkStorageFailed, object: error)
                }
            }
            return false
        }
    }
    func flush() throws {
        lock.lock(); defer { lock.unlock() }
        if let readError { throw readError }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

extension Notification.Name {
    static let dayPerkStorageFailed = Notification.Name("DayPerkStorageFailed")
}
