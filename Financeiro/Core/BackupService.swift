import Foundation
import CryptoKit
import CommonCrypto
import Security

enum BackupService {
    static let maximumFileSize = 20 * 1_024 * 1_024
    // Leaves room for Base64 and the authenticated envelope within the 20 MiB file cap.
    static let maximumPlaintextSize = 14 * 1_024 * 1_024
    private static let iterations = 600_000
    private static let authenticatedHeader = Data("Financeiro/v1/AES-256-GCM/PBKDF2-HMAC-SHA256/600000".utf8)

    private struct Envelope: Codable {
        let version: Int
        let algorithm: String
        let kdf: String
        let iterations: Int
        let salt: Data
        /// CryptoKit combined representation contains the random nonce and authentication tag.
        let sealed: Data
    }

    static func encrypt(transactions: [FinanceTransaction], password: String) throws -> Data {
        try validate(password: password)
        try validate(transactions: transactions)
        let plaintext = try JSONEncoder().encode(transactions)
        guard plaintext.count <= maximumPlaintextSize else { throw BackupError.fileTooLarge }
        var salt = Data(count: 16)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw BackupError.cryptographyFailure }
        let key = try deriveKey(password: password, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(),
                                   authenticating: authenticatedHeader)
        guard let combined = box.combined else { throw BackupError.cryptographyFailure }
        let envelope = Envelope(version: 1, algorithm: "AES-256-GCM", kdf: "PBKDF2-HMAC-SHA256",
                                iterations: iterations, salt: salt, sealed: combined)
        let output = try JSONEncoder().encode(envelope)
        guard output.count <= maximumFileSize else { throw BackupError.fileTooLarge }
        return output
    }

    /// Fully decrypts, decodes, and validates before the caller may mutate the store.
    static func decrypt(data: Data, password: String) throws -> [FinanceTransaction] {
        guard data.count <= maximumFileSize else { throw BackupError.fileTooLarge }
        try validate(password: password)
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw BackupError.invalidFormat }
        guard envelope.version == 1 else { throw BackupError.unsupportedVersion }
        // Never honor an attacker-selected KDF cost or allocation size.
        guard envelope.algorithm == "AES-256-GCM", envelope.kdf == "PBKDF2-HMAC-SHA256",
              envelope.iterations == iterations, envelope.salt.count == 16,
              envelope.sealed.count >= 28, envelope.sealed.count <= maximumFileSize else {
            throw BackupError.invalidFormat
        }
        let key = try deriveKey(password: password, salt: envelope.salt)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealed)
            plaintext = try AES.GCM.open(box, using: key, authenticating: authenticatedHeader)
        } catch { throw BackupError.incorrectPasswordOrCorrupted }
        let transactions: [FinanceTransaction]
        do { transactions = try JSONDecoder().decode([FinanceTransaction].self, from: plaintext) }
        catch { throw BackupError.invalidFormat }
        try validate(transactions: transactions)
        return transactions
    }

    private static func validate(password: String) throws {
        guard password.count >= 12, password.utf8.count <= 1_024 else { throw BackupError.weakPassword }
    }

    private static func validate(transactions: [FinanceTransaction]) throws {
        guard transactions.count <= TransactionStore.maximumTransactions else { throw FinanceDataError.tooManyTransactions }
        guard Set(transactions.map(\.id)).count == transactions.count else { throw FinanceDataError.duplicateIdentifier }
        for transaction in transactions { try transaction.validate() }
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        var passwordBytes = Array(password.utf8)
        var keyBytes = [UInt8](repeating: 0, count: 32)
        defer {
            // Best effort cleanup of mutable derivation buffers; Swift strings are value types.
            passwordBytes.withUnsafeMutableBytes { buffer in
                if let address = buffer.baseAddress { memset_s(address, buffer.count, 0, buffer.count) }
            }
            keyBytes.withUnsafeMutableBytes { buffer in
                if let address = buffer.baseAddress { memset_s(address, buffer.count, 0, buffer.count) }
            }
        }
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                keyBytes.withUnsafeMutableBytes { keyBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self), passwordBuffer.count,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        keyBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), keyBuffer.count)
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.cryptographyFailure }
        return SymmetricKey(data: keyBytes)
    }
}

enum BackupError: LocalizedError {
    case weakPassword
    case fileTooLarge
    case invalidFormat
    case unsupportedVersion
    case incorrectPasswordOrCorrupted
    case cryptographyFailure

    var errorDescription: String? {
        switch self {
        case .weakPassword: return "Use uma senha com pelo menos 12 caracteres e no máximo 1.024 bytes."
        case .fileTooLarge: return "O arquivo excede o limite de 20 MB."
        case .invalidFormat: return "O arquivo não é um backup válido do Financeiro."
        case .unsupportedVersion: return "Esta versão de backup ainda não é compatível."
        case .incorrectPasswordOrCorrupted: return "Senha incorreta ou arquivo alterado."
        case .cryptographyFailure: return "Não foi possível proteger o backup."
        }
    }
}
