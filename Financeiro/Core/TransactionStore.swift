import Foundation
import SQLite3

/// SQLite is accessed only while holding lock. No connection or statement escapes.
final class TransactionStore: @unchecked Sendable {
    static let maximumTransactions = 100_000
    private let lock = NSLock()
    private var connection: OpaquePointer?
    private let url: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    convenience init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        try self.init(url: base.appendingPathComponent("Financeiro", isDirectory: true)
            .appendingPathComponent("transactions.sqlite"))
    }

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try protect(url.deletingLastPathComponent())
        try excludeFromSystemBackup(url.deletingLastPathComponent())
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle,
                                     SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw StoreError.database("Não foi possível abrir os dados locais.")
        }
        connection = handle
        do {
            try check(sqlite3_busy_timeout(handle, 5_000))
            try validateSchemaVersion()
            // DELETE avoids persistent unprotected sidecar files and is adequate for this single local writer.
            try execute("PRAGMA journal_mode = DELETE")
            try execute("PRAGMA synchronous = FULL")
            try execute("PRAGMA secure_delete = ON")
            try execute("""
                CREATE TABLE IF NOT EXISTS transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    amount INTEGER NOT NULL CHECK(typeof(amount) = 'integer' AND amount > 0),
                    currency TEXT NOT NULL,
                    merchant TEXT NOT NULL,
                    date REAL NOT NULL,
                    kind TEXT NOT NULL CHECK(kind IN ('income','expense','transfer')),
                    category TEXT NOT NULL,
                    account TEXT NOT NULL,
                    source TEXT NOT NULL CHECK(source IN ('manual','shortcut','imported')),
                    note TEXT NOT NULL,
                    encoded_bytes INTEGER NOT NULL CHECK(encoded_bytes > 0)
                )
                """)
            try migrateSnapshotBudgetIfNeeded()
            try validateCapacity()
            try execute("CREATE INDEX IF NOT EXISTS transactions_date ON transactions(date DESC)")
            try execute("PRAGMA user_version = 1")
            try protect(url)
            try excludeFromSystemBackup(url)
        } catch {
            sqlite3_close(handle)
            connection = nil
            throw error
        }
    }

    deinit { if let connection { sqlite3_close(connection) } }

    func all() throws -> [FinanceTransaction] {
        try locked {
            let statement = try prepare("SELECT id, amount, currency, merchant, date, kind, category, account, source, note FROM transactions ORDER BY date DESC, id ASC")
            defer { sqlite3_finalize(statement) }
            var records: [FinanceTransaction] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return records }
                guard status == SQLITE_ROW else { throw databaseError() }
                guard sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
                      let id = UUID(uuidString: string(statement, 0)),
                      let kind = TransactionKind(rawValue: string(statement, 5)),
                      let source = TransactionSource(rawValue: string(statement, 8)) else {
                    throw StoreError.invalidData
                }
                let transaction = FinanceTransaction(id: id, amountMinor: sqlite3_column_int64(statement, 1),
                    currency: string(statement, 2), merchant: string(statement, 3),
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    kind: kind, category: string(statement, 6), account: string(statement, 7),
                    source: source, note: string(statement, 9))
                try transaction.validate()
                records.append(transaction)
            }
        }
    }

    @discardableResult
    func add(_ transaction: FinanceTransaction) throws -> Bool {
        try transaction.validate()
        return try locked {
            try atomic {
                let inserted = try insert(transaction)
                try validateCapacity()
                return inserted
            }
        }
    }

    func update(_ transaction: FinanceTransaction) throws {
        try transaction.validate()
        try locked {
            try atomic {
                let statement = try prepare("UPDATE transactions SET amount=?, currency=?, merchant=?, date=?, kind=?, category=?, account=?, source=?, note=?, encoded_bytes=? WHERE id=?")
                defer { sqlite3_finalize(statement) }
                try bindFields(transaction, to: statement, offset: 0)
                try check(sqlite3_bind_int64(statement, 10, try encodedBudget(transaction)))
                try bind(transaction.id.uuidString, to: statement, at: 11)
                try checkDone(statement)
                guard sqlite3_changes(connection) == 1 else { throw FinanceDataError.missingTransaction }
                try validateCapacity()
            }
        }
    }

    func delete(id: UUID) throws {
        try locked {
            let statement = try prepare("DELETE FROM transactions WHERE id=?")
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, to: statement, at: 1)
            try checkDone(statement)
        }
    }

    func replaceAll(_ transactions: [FinanceTransaction]) throws {
        try validate(transactions)
        guard Set(transactions.map(\.id)).count == transactions.count else { throw FinanceDataError.duplicateIdentifier }
        try locked {
            try atomic {
                try execute("DELETE FROM transactions")
                for transaction in transactions { _ = try insert(transaction) }
                try validateCapacity()
            }
        }
    }

    @discardableResult
    func merge(_ transactions: [FinanceTransaction]) throws -> Int {
        try validate(transactions)
        return try locked {
            try atomic {
                var inserted = 0
                for transaction in transactions { if try insert(transaction) { inserted += 1 } }
                try validateCapacity()
                return inserted
            }
        }
    }

    private func validate(_ transactions: [FinanceTransaction]) throws {
        guard transactions.count <= Self.maximumTransactions else { throw FinanceDataError.tooManyTransactions }
        var budget: Int64 = 2
        for transaction in transactions {
            try transaction.validate()
            budget += try encodedBudget(transaction) + 1
            guard budget <= Int64(BackupService.maximumPlaintextSize) else { throw FinanceDataError.backupCapacityExceeded }
        }
    }

    private func validateCapacity() throws {
        let statement = try prepare("SELECT COUNT(*), COALESCE(SUM(encoded_bytes), 0) + COUNT(*) + 2 FROM transactions")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        guard sqlite3_column_int64(statement, 0) <= Int64(Self.maximumTransactions) else { throw FinanceDataError.tooManyTransactions }
        guard sqlite3_column_int64(statement, 1) <= Int64(BackupService.maximumPlaintextSize) else { throw FinanceDataError.backupCapacityExceeded }
    }

    // Limits are both record count and encoded size. The margin absorbs future JSON
    // encoding changes; each accepted snapshot remains exportable below 20 MiB.
    private func encodedBudget(_ transaction: FinanceTransaction) throws -> Int64 {
        Int64(try JSONEncoder().encode(transaction).count) + 64
    }

    private func migrateSnapshotBudgetIfNeeded() throws {
        let statement = try prepare("PRAGMA table_info(transactions)")
        var found = false
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { sqlite3_finalize(statement); throw databaseError() }
            if string(statement, 1) == "encoded_bytes" { found = true }
        }
        sqlite3_finalize(statement)
        guard !found else { return }
        // Schema 1 builds made before the first release have no size accounting.
        // Validate and backfill atomically; an oversized old database is preserved.
        let existing = try all()
        try validate(existing)
        try atomic {
            try execute("ALTER TABLE transactions ADD COLUMN encoded_bytes INTEGER NOT NULL DEFAULT 0")
            let update = try prepare("UPDATE transactions SET encoded_bytes=? WHERE id=?")
            defer { sqlite3_finalize(update) }
            for transaction in existing {
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                try check(sqlite3_bind_int64(update, 1, try encodedBudget(transaction)))
                try bind(transaction.id.uuidString, to: update, at: 2)
                try checkDone(update)
            }
            try validateCapacity()
        }
    }

    private func validateSchemaVersion() throws {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        guard sqlite3_column_int(statement, 0) <= 1 else { throw StoreError.unsupportedSchema }
    }

    private func insert(_ transaction: FinanceTransaction) throws -> Bool {
        let statement = try prepare("INSERT INTO transactions (id, amount, currency, merchant, date, kind, category, account, source, note, encoded_bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING")
        defer { sqlite3_finalize(statement) }
        try bind(transaction.id.uuidString, to: statement, at: 1)
        try bindFields(transaction, to: statement, offset: 1)
        try check(sqlite3_bind_int64(statement, 11, try encodedBudget(transaction)))
        try checkDone(statement)
        return sqlite3_changes(connection) == 1
    }

    /// The nine mutable fields always occupy contiguous positions.
    private func bindFields(_ transaction: FinanceTransaction, to statement: OpaquePointer, offset: Int32) throws {
        try check(sqlite3_bind_int64(statement, offset + 1, transaction.amountMinor))
        try bind(transaction.currency, to: statement, at: offset + 2)
        try bind(transaction.merchant, to: statement, at: offset + 3)
        try check(sqlite3_bind_double(statement, offset + 4, transaction.date.timeIntervalSince1970))
        try bind(transaction.kind.rawValue, to: statement, at: offset + 5)
        try bind(transaction.category, to: statement, at: offset + 6)
        try bind(transaction.account, to: statement, at: offset + 7)
        try bind(transaction.source.rawValue, to: statement, at: offset + 8)
        try bind(transaction.note, to: statement, at: offset + 9)
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    private func atomic<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(connection, sql, -1, &statement, nil))
        guard let statement else { throw databaseError() }
        return statement
    }

    private func execute(_ sql: String) throws { try check(sqlite3_exec(connection, sql, nil, nil, nil)) }
    private func check(_ status: Int32) throws { guard status == SQLITE_OK else { throw databaseError() } }
    private func checkDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        try check(value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) })
    }
    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }
    private func databaseError() -> StoreError {
        // SQLite messages may include application data; do not expose or log them.
        StoreError.database("Não foi possível acessar os dados locais (código \(sqlite3_errcode(connection))).")
    }

    private func protect(_ path: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
    }

    private func excludeFromSystemBackup(_ path: URL) throws {
        #if os(iOS)
        var resource = path
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        #endif
    }
}

enum StoreError: LocalizedError {
    case database(String)
    case invalidData
    case unsupportedSchema
    var errorDescription: String? {
        switch self {
        case .database(let message): return message
        case .invalidData: return "Os dados locais contêm um lançamento inválido."
        case .unsupportedSchema: return "Estes dados foram criados por uma versão mais recente do Financeiro. Atualize o aplicativo."
        }
    }
}
