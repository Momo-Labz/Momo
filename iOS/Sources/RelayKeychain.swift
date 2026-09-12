import Foundation
import Security

struct RelayCredential: Codable, Equatable {
    let statusURL: URL
    let token: String

    init?(pairingAddress: String) {
        let cleaned = pairingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: cleaned),
              components.scheme == "http" || components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.host != nil,
              let token = components.queryItems?.first(where: { $0.name == "key" })?.value,
              Self.isValidToken(token) else { return nil }
        components.path = "/api/status"
        components.queryItems = nil
        components.fragment = nil
        guard let statusURL = components.url else { return nil }
        self.statusURL = statusURL
        self.token = token
    }

    var pairingAddress: String {
        guard var components = URLComponents(url: statusURL, resolvingAgainstBaseURL: false) else { return "" }
        components.path = "/display"
        components.queryItems = [URLQueryItem(name: "key", value: token)]
        return components.url?.absoluteString ?? ""
    }

    private static func isValidToken(_ token: String) -> Bool {
        (20...128).contains(token.utf8.count)
            && token.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) }
    }
}

enum RelayKeychain {
    private static let service = "com.momolabz.barboy.mobile"
    private static let account = "paired-status-url"

    static func save(_ credential: RelayCredential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> RelayCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        if let credential = try? JSONDecoder().decode(RelayCredential.self, from: data) {
            return credential
        }
        // Migrate the 0.3 Keychain value, which stored the full query URL.
        guard let legacyAddress = String(data: data, encoding: .utf8) else { return nil }
        return RelayCredential(pairingAddress: legacyAddress)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
