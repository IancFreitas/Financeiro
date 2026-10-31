import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case income, expense, transfer
    var id: String { rawValue }
}

enum TransactionSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, shortcut, imported
    var id: String { rawValue }
}

struct FinanceTransaction: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var amountMinor: Int64
    var currency: String
    var merchant: String
    var date: Date
    var kind: TransactionKind
    var category: String
    var account: String
    var source: TransactionSource
    var note: String

    init(id: UUID = UUID(), amountMinor: Int64, currency: String = "BRL",
         merchant: String, date: Date = Date(), kind: TransactionKind,
         category: String, account: String, source: TransactionSource, note: String = "") {
        self.id = id
        self.amountMinor = amountMinor
        self.currency = currency
        self.merchant = merchant
        self.date = date
        self.kind = kind
        self.category = category
        self.account = account
        self.source = source
        self.note = note
    }

    func validate() throws {
        guard amountMinor > 0 else { throw FinanceDataError.invalidAmount }
        guard currency.utf8.count == 3,
              currency.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw FinanceDataError.invalidField("moeda")
        }
        guard date.timeIntervalSince1970.isFinite else { throw FinanceDataError.invalidField("data") }
        for (name, value, limit) in [("estabelecimento", merchant, 200),
                                     ("categoria", category, 100), ("conta", account, 100)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.count <= limit, !value.contains("\0") else {
                throw FinanceDataError.invalidField(name)
            }
        }
        guard note.count <= 4_000, !note.contains("\0") else { throw FinanceDataError.invalidField("observação") }
    }
}

enum FinanceDataError: LocalizedError {
    case invalidAmount
    case invalidField(String)
    case tooManyTransactions
    case duplicateIdentifier
    case missingTransaction
    case arithmeticOverflow
    case backupCapacityExceeded

    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Informe um valor positivo em reais, como 123,45."
        case .invalidField(let field): return "O campo \(field) é inválido."
        case .tooManyTransactions: return "O limite é de 100.000 lançamentos."
        case .duplicateIdentifier: return "Há identificadores repetidos no arquivo."
        case .missingTransaction: return "O lançamento não existe mais."
        case .arithmeticOverflow: return "O total excede o limite suportado."
        case .backupCapacityExceeded: return "O espaço para lançamentos chegou ao limite de backup seguro (14 MB de dados). Exporte uma cópia e remova registros antes de adicionar mais."
        }
    }
}

enum Money {
    /// Parses only Brazilian notation, without rounding or floating-point conversion.
    static func parseBRL(_ input: String) throws -> Int64 {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty else { throw FinanceDataError.invalidAmount }
        let whole = parts[0]
        let groups = whole.split(separator: ".", omittingEmptySubsequences: false)
        let asciiDigits: (Substring) -> Bool = { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
        guard groups.allSatisfy(asciiDigits) else { throw FinanceDataError.invalidAmount }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { throw FinanceDataError.invalidAmount }
        }
        let fraction: String
        if parts.count == 2 {
            guard (1...2).contains(parts[1].count), asciiDigits(parts[1]) else { throw FinanceDataError.invalidAmount }
            fraction = String(parts[1]) + (parts[1].count == 1 ? "0" : "")
        } else {
            fraction = "00"
        }
        let digits = groups.joined() + fraction
        guard let amount = Int64(digits), amount > 0 else { throw FinanceDataError.invalidAmount }
        return amount
    }

    /// Exact integer formatting, including Int64.min, without Double precision loss.
    static func format(_ amountMinor: Int64, currency: String = "BRL") -> String {
        let magnitude = amountMinor.magnitude
        let whole = String(magnitude / 100)
        var grouped = ""
        for (index, character) in whole.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(".") }
            grouped.append(character)
        }
        let fraction = magnitude % 100
        let symbol = currency == "BRL" ? "R$" : currency
        return "\(amountMinor < 0 ? "−" : "")\(symbol) \(String(grouped.reversed())),\(fraction < 10 ? "0" : "")\(fraction)"
    }

    static func sum<S: Sequence>(_ amounts: S) throws -> Int64 where S.Element == Int64 {
        try amounts.reduce(Int64(0)) { total, amount in
            let (value, overflow) = total.addingReportingOverflow(amount)
            guard !overflow else { throw FinanceDataError.arithmeticOverflow }
            return value
        }
    }
}
