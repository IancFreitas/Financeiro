import Foundation
import Security

/// An opportunistic, encrypted copy to a user-selected Files folder.
/// Call off the main thread after writes and on foreground entry; this is not a
/// permanent timer. Files providers, revoked folder access, a locked database,
/// and the first device unlock after boot can prevent a copy. A successful write
/// means the file was saved to the folder, not that iCloud finished uploading it.
/// The password stays on this device in Keychain; keep a separate recovery copy.
final class AutomaticBackup: @unchecked Sendable {
    static let shared = AutomaticBackup()

    private struct Configuration: Codable {
        let bookmark: Data
        let credentialID: String
    }

    private enum Failure: LocalizedError {
        case password, folder, configuration, credential, snapshot, encryption, write

        var errorDescription: String? {
            switch self {
            case .password: return "Use uma senha de pelo menos 12 caracteres e no máximo 1.024 bytes UTF-8."
            case .folder: return "Não foi possível acessar a pasta. Escolha-a novamente em Arquivos."
            case .configuration: return "Não foi possível salvar a configuração da cópia automática."
            case .credential: return "Não foi possível acessar a senha no dispositivo. Desbloqueie-o ou configure a cópia novamente."
            case .snapshot: return "Não foi possível ler os dados locais para criar a cópia."
            case .encryption: return "Não foi possível criptografar a cópia."
            case .write: return "Não foi possível gravar a cópia na pasta escolhida. Tente novamente."
            }
        }
    }

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let configurationKey = "automaticBackup.configuration.v1"
    private let successKey = "automaticBackup.lastLocalSuccess.v1"
    private let errorKey = "automaticBackup.lastError.v1"
    private let service = "Financeiro.AutomaticBackup.v1"

    private init() {}

    /// Both a stored bookmark and a readable device-only credential are required.
    /// This does not guarantee that the file provider is currently available.
    var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let configuration = configuration() else { return false }
        return (try? password(for: configuration.credentialID)) != nil
    }

    var statusDescription: String {
        lock.lock()
        defer { lock.unlock() }
        guard configuration() != nil else { return "Cópia automática desativada." }
        var message: String
        if let date = defaults.object(forKey: successKey) as? Date {
            message = "Última cópia gravada na pasta: \(date.formatted(date: .abbreviated, time: .shortened))."
        } else {
            message = "Ainda não foi gravada uma cópia automática."
        }
        if let error = defaults.string(forKey: errorKey) { message += " \(error)" }
        return message + " O envio ao iCloud depende do iOS."
    }

    static func validatePassword(_ password: String) throws {
        guard password.count >= 12, password.utf8.count <= 1_024 else { throw Failure.password }
    }

    func configure(folder: URL, password: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try Self.validatePassword(password)
        guard folder.isFileURL, folder.startAccessingSecurityScopedResource() else { throw Failure.folder }
        defer { folder.stopAccessingSecurityScopedResource() }

        let bookmark: Data
        do {
            guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw Failure.folder }
            // Unlike macOS's .withSecurityScope, .minimalBookmark is supported on iOS.
            bookmark = try folder.bookmarkData(options: .minimalBookmark,
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
            var stale = false
            _ = try URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                        relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { throw Failure.folder }
        } catch { throw Failure.folder }

        let old = configuration()
        let credentialID = UUID().uuidString
        let encoded: Data
        do { encoded = try PropertyListEncoder().encode(Configuration(bookmark: bookmark, credentialID: credentialID)) }
        catch { throw Failure.configuration }
        try savePassword(password, identifier: credentialID)
        // Publish only after Keychain succeeds. Failures before publication leave
        // the previous bookmark/credential pair usable.
        defaults.set(encoded, forKey: configurationKey)
        guard defaults.data(forKey: configurationKey) == encoded else {
            try? deletePassword(identifier: credentialID)
            throw Failure.configuration
        }
        defaults.removeObject(forKey: successKey)
        defaults.removeObject(forKey: errorKey)
        if let old { try? deletePassword(identifier: old.credentialID) }
    }

    /// Does not delete existing backup files or any transaction data.
    func disable() throws {
        lock.lock()
        defer { lock.unlock() }
        let old = configuration()
        // Disable first, even if Keychain is temporarily inaccessible.
        defaults.removeObject(forKey: configurationKey)
        defaults.removeObject(forKey: successKey)
        defaults.removeObject(forKey: errorKey)
        if let old { try deletePassword(identifier: old.credentialID) }
    }

    /// A no-op when disabled. Call independently from the database save result.
    func run() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let configuration = configuration() else { return }
        do {
            let password = try password(for: configuration.credentialID)
            let folder: URL
            do {
                var stale = false
                folder = try URL(resolvingBookmarkData: configuration.bookmark,
                                 options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale else { throw Failure.folder }
            } catch { throw Failure.folder }
            guard folder.startAccessingSecurityScopedResource() else { throw Failure.folder }
            defer { folder.stopAccessingSecurityScopedResource() }

            try write(to: folder, password: password)
            // The timestamp is updated only after coordinated atomic writing succeeds.
            defaults.set(Date(), forKey: successKey)
            defaults.removeObject(forKey: errorKey)
        } catch {
            let failure = (error as? Failure) ?? .write
            // Fixed messages only: no transaction text, password, or filesystem URL.
            defaults.set(failure.localizedDescription, forKey: errorKey)
            throw failure
        }
    }

    private func write(to folder: URL, password: String) throws {
        let latest = folder.appendingPathComponent("Financeiro-latest.financeiro")
        let previous = folder.appendingPathComponent("Financeiro-previous.financeiro")
        var coordinationError: NSError?
        var didWrite = false
        var operationFailure: Failure?
        NSFileCoordinator().coordinate(writingItemAt: latest, options: .forReplacing,
                                       writingItemAt: previous, options: .forReplacing,
                                       error: &coordinationError) { latestURL, previousURL in
            do {
                // Snapshot only after acquiring file coordination, so an older
                // snapshot cannot overwrite a newer backup from another process.
                let transactions: [FinanceTransaction]
                do { transactions = try TransactionStore().all() }
                catch { throw Failure.snapshot }
                let encrypted: Data
                do { encrypted = try BackupService.encrypt(transactions: transactions, password: password) }
                catch { throw Failure.encryption }
                // Best effort retention, with a bounded read of external input.
                // Only ciphertext leaves the app container.
                if let old = try? readPrevious(at: latestURL) {
                    try? old.write(to: previousURL, options: .atomic)
                }
                try encrypted.write(to: latestURL, options: .atomic)
                didWrite = true
            } catch { operationFailure = (error as? Failure) ?? .write }
        }
        if let operationFailure { throw operationFailure }
        guard coordinationError == nil, didWrite else { throw Failure.write }
    }

    private func readPrevious(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximum = BackupService.maximumFileSize
        guard try handle.seekToEnd() <= UInt64(maximum) else { throw Failure.write }
        try handle.seek(toOffset: 0)
        var data = Data()
        // The bound also applies if another actor grows the file after seekToEnd.
        while let chunk = try handle.read(upToCount: min(65_536, maximum + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximum else { throw Failure.write }
        }
        guard !data.isEmpty else { throw Failure.write }
        return data
    }

    private func configuration() -> Configuration? {
        guard let data = defaults.data(forKey: configurationKey) else { return nil }
        return try? PropertyListDecoder().decode(Configuration.self, from: data)
    }

    private func query(identifier: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: identifier,
         kSecAttrSynchronizable as String: false]
    }

    private func savePassword(_ password: String, identifier: String) throws {
        var item = query(identifier: identifier)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.credential }
        do { _ = try self.password(for: identifier) }
        catch {
            try? deletePassword(identifier: identifier)
            throw Failure.credential
        }
    }

    private func password(for identifier: String) throws -> String {
        var item = query(identifier: identifier)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let password = String(data: data, encoding: .utf8),
              password.count >= 12, password.utf8.count <= 1_024 else { throw Failure.credential }
        return password
    }

    private func deletePassword(identifier: String) throws {
        let status = SecItemDelete(query(identifier: identifier) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.credential }
    }
}
