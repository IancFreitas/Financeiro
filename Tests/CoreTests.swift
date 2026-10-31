import XCTest
import SQLite3
@testable import Financeiro

final class MoneyTests: XCTestCase {
    func testBrazilianMoneyIsParsedWithoutFloatingPoint() throws {
        XCTAssertEqual(try Money.parseBRL("1.234,56"), 123_456)
        XCTAssertEqual(try Money.parseBRL(" 12 "), 1_200)
        XCTAssertEqual(try Money.parseBRL("0,01"), 1)
        XCTAssertEqual(try Money.parseBRL("12,3"), 1_230)
        XCTAssertEqual(try Money.parseBRL("92233720368547758,07"), Int64.max)
    }

    func testInvalidValuesAndOverflowAreRejected() {
        for input in ["", "0", "0,00", "-1", "+1", "NaN", "inf", "1.23", "1,234", "1,", ",50",
                      "12.34,56", "1 000,00", "1e3", "92233720368547758,08", "9223372036854775807"] {
            XCTAssertThrowsError(try Money.parseBRL(input), "Accepted: \(input)")
        }
    }

    func testFormattingAndSumStayExactAtIntegerLimits() throws {
        XCTAssertEqual(Money.format(Int64.max), "R$ 92.233.720.368.547.758,07")
        XCTAssertEqual(Money.format(Int64.min), "−R$ 92.233.720.368.547.758,08")
        XCTAssertEqual(try Money.sum([100, 25, -10]), 115)
        XCTAssertThrowsError(try Money.sum([Int64.max, 1]))
        XCTAssertThrowsError(try Money.sum([Int64.min, -1]))
    }
}

final class TransactionStoreTests: XCTestCase {
    func testPersistenceAndIdentifierOnlyDeduplication() throws {
        try withDatabase { url in
            let original = sampleTransaction()
            var first: TransactionStore? = try TransactionStore(url: url)
            XCTAssertTrue(try first!.add(original))
            XCTAssertFalse(try first!.add(original))
            var samePurchaseDetails = original
            samePurchaseDetails.id = UUID()
            XCTAssertTrue(try first!.add(samePurchaseDetails))
            first = nil
            let reopened = try TransactionStore(url: url)
            XCTAssertEqual(Set(try reopened.all().map(\.id)), Set([original.id, samePurchaseDetails.id]))
        }
    }

    func testMergeUpdateAndDelete() throws {
        try withDatabase { url in
            let store = try TransactionStore(url: url)
            let original = sampleTransaction()
            let second = sampleTransaction()
            XCTAssertEqual(try store.merge([original, original, second]), 2)
            XCTAssertEqual(try store.merge([original]), 0)
            var updated = original
            updated.amountMinor = 9_999
            updated.note = "Corrigido"
            try store.update(updated)
            XCTAssertEqual(try store.all().first(where: { $0.id == original.id }), updated)
            try store.delete(id: second.id)
            XCTAssertEqual(try store.all().count, 1)
            XCTAssertThrowsError(try store.update(second))
        }
    }

    func testInvalidRestoreAndMergeKeepExistingRecords() throws {
        try withDatabase { url in
            let store = try TransactionStore(url: url)
            let original = sampleTransaction()
            try store.add(original)
            var invalid = sampleTransaction()
            invalid.amountMinor = 0
            XCTAssertThrowsError(try store.replaceAll([sampleTransaction(), invalid]))
            XCTAssertThrowsError(try store.merge([sampleTransaction(), invalid]))
            XCTAssertThrowsError(try store.replaceAll([original, original]))
            XCTAssertEqual(try store.all(), [original])
        }
    }

    func testSQLFailureRollsBackWholeReplacementAndMerge() throws {
        try withDatabase { url in
            let store = try TransactionStore(url: url)
            let original = sampleTransaction()
            try store.add(original)
            var handle: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
            defer { sqlite3_close(handle) }
            let sql = "CREATE TRIGGER fail_insert BEFORE INSERT ON transactions WHEN NEW.merchant = 'Falha' BEGIN SELECT RAISE(ABORT, 'test'); END"
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
            var rejected = sampleTransaction()
            rejected.merchant = "Falha"
            XCTAssertThrowsError(try store.replaceAll([sampleTransaction(), rejected]))
            XCTAssertEqual(try store.all(), [original])
            XCTAssertThrowsError(try store.merge([sampleTransaction(), rejected]))
            XCTAssertEqual(try store.all(), [original])
        }
    }

    func testConcurrentWritesAreSerialized() throws {
        try withDatabase { url in
            let store = try TransactionStore(url: url)
            let transactions = (0..<100).map { _ in sampleTransaction() }
            DispatchQueue.concurrentPerform(iterations: transactions.count) { index in
                _ = try? store.add(transactions[index])
            }
            XCTAssertEqual(try store.all().count, transactions.count)
        }
    }

    func testFutureSchemaIsRejectedWithoutDowngrading() throws {
        try withDatabase { url in
            let store = try TransactionStore(url: url)
            let original = sampleTransaction()
            try store.add(original)
            var handle: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
            defer { sqlite3_close(handle) }
            XCTAssertEqual(sqlite3_exec(handle, "PRAGMA user_version = 2", nil, nil, nil), SQLITE_OK)
            XCTAssertThrowsError(try TransactionStore(url: url))
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
            XCTAssertEqual(try store.all(), [original])
        }
    }
}

final class BackupServiceTests: XCTestCase {
    private let password = "uma-senha-longa-de-teste"

    func testEncryptedRoundTripAndRandomization() throws {
        let transactions = [sampleTransaction(), sampleTransaction(amount: Int64.max)]
        let first = try BackupService.encrypt(transactions: transactions, password: password)
        let second = try BackupService.encrypt(transactions: transactions, password: password)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("Mercado Exemplo"))
        XCTAssertEqual(try BackupService.decrypt(data: first, password: password), transactions)
    }

    func testIncorrectPasswordAndTamperingAreRejected() throws {
        let encrypted = try BackupService.encrypt(transactions: [sampleTransaction()], password: password)
        XCTAssertThrowsError(try BackupService.decrypt(data: encrypted, password: "outra-senha-incorreta"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        let base64 = try XCTUnwrap(json["sealed"] as? String)
        var sealed = try XCTUnwrap(Data(base64Encoded: base64))
        sealed[sealed.count - 1] ^= 0x01
        json["sealed"] = sealed.base64EncodedString()
        XCTAssertThrowsError(try BackupService.decrypt(data: JSONSerialization.data(withJSONObject: json), password: password))
    }

    func testUnsupportedVersionAndAttackerSelectedCostAreRejected() throws {
        let encrypted = try BackupService.encrypt(transactions: [], password: password)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        json["version"] = 2
        XCTAssertThrowsError(try BackupService.decrypt(data: JSONSerialization.data(withJSONObject: json), password: password))
        json["version"] = 1
        json["iterations"] = Int.max
        XCTAssertThrowsError(try BackupService.decrypt(data: JSONSerialization.data(withJSONObject: json), password: password))
    }

    func testWeakPasswordInvalidDataAndOversizedFilesAreRejected() {
        XCTAssertThrowsError(try BackupService.encrypt(transactions: [], password: "curta"))
        XCTAssertThrowsError(try BackupService.decrypt(data: Data("{}".utf8), password: password))
        XCTAssertThrowsError(try BackupService.decrypt(data: Data(repeating: 0, count: BackupService.maximumFileSize + 1), password: password))
        var invalid = sampleTransaction()
        invalid.amountMinor = -1
        XCTAssertThrowsError(try BackupService.encrypt(transactions: [invalid], password: password))
    }
}

private func sampleTransaction(amount: Int64 = 1_299) -> FinanceTransaction {
    FinanceTransaction(amountMinor: amount, merchant: "Mercado Exemplo", date: Date(timeIntervalSince1970: 1_700_000_000),
                       kind: .expense, category: "Alimentação", account: "Principal", source: .manual)
}

private func withDatabase(_ work: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try work(directory.appendingPathComponent("transactions.sqlite"))
}
