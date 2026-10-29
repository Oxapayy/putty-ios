import Foundation
import Security

/// Saved sessions, like PuTTY's registry entries. Passwords are never stored.
enum SessionStore {
    static let defaultName = "Default Settings"
    private static let key = "putty.sessions"

    private static var all: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var names: [String] {
        [defaultName] + all.keys.filter { $0 != defaultName }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func load(_ name: String) -> SessionConfig {
        guard let data = all[name], let cfg = SessionConfig.decode(data) else { return SessionConfig() }
        return cfg
    }

    static func save(_ cfg: SessionConfig, as name: String) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        all[name] = data
    }

    static func delete(_ name: String) {
        guard name != defaultName else { return }
        if let keyID = load(name).keyID, !isKeyShared(keyID, except: name) {
            KeyStore.delete(id: keyID)
        }
        all[name] = nil
    }

    private static func isKeyShared(_ keyID: String, except name: String) -> Bool {
        all.contains { $0.key != name && SessionConfig.decode($0.value)?.keyID == keyID }
    }
}

/// PuTTY's host key cache ("known hosts").
enum HostKeyStore {
    private static let key = "putty.hostkeys"

    private static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private static func id(_ host: String, _ port: Int) -> String { "\(host.lowercased()):\(port)" }

    static func get(host: String, port: Int) -> String? { all[id(host, port)] }
    static func set(_ openSSHKey: String, host: String, port: Int) { all[id(host, port)] = openSSHKey }
    static func remove(host: String, port: Int) { all[id(host, port)] = nil }
}

/// Private key files live in the Keychain, readable only while the device is unlocked.
/// Sideloaded builds without a keychain entitlement fall back to a file with complete data protection.
enum KeyStore {
    private static let service = "putty.privatekeys"

    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id]
    }

    private static func fileURL(_ id: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("keys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(values)
        return dir.appendingPathComponent(id)
    }

    static func add(_ data: Data) -> String? {
        let id = UUID().uuidString
        var q = query(id)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return id }
        guard let url = fileURL(id), (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        return id
    }

    static func get(id: String) -> Data? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data { return data }
        return fileURL(id).flatMap { try? Data(contentsOf: $0) }
    }

    static func delete(id: String) {
        SecItemDelete(query(id) as CFDictionary)
        if let url = fileURL(id) { try? FileManager.default.removeItem(at: url) }
    }
}
