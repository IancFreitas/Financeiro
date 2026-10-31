import CryptoKit
import Foundation

enum CSVImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return "CSV inválido: \(reason)" }
    }
}

/// An explicit interchange format, not a heuristic parser for arbitrary bank statements.
/// The complete file is validated before the UI can offer an atomic merge.
enum CSVImporter {
    static let maximumBytes = 20 * 1_024 * 1_024

    static func parse(_ text: String) throws -> [FinanceTransaction] {
        guard text.utf8.count <= maximumBytes else { throw CSVImportError.invalid("limite de 20 MB.") }
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = clean.prefix(while: { !$0.isNewline })
        let delimiter: Character = firstLine.contains(";") ? ";" : ","
        var rows = try fields(clean, delimiter: delimiter)
        guard !rows.isEmpty else { throw CSVImportError.invalid("arquivo vazio.") }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(header).count == header.count else { throw CSVImportError.invalid("colunas repetidas.") }
        let required = ["date", "merchant", "amount", "kind"]
        guard required.allSatisfy(header.contains) else {
            throw CSVImportError.invalid("use as colunas date;merchant;amount;kind. Veja o modelo do projeto.")
        }
        let allowed = Set(required + ["id", "category", "account", "currency", "note"])
        guard header.allSatisfy(allowed.contains) else { throw CSVImportError.invalid("coluna desconhecida.") }
        let indices = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        guard rows.count <= TransactionStore.maximumTransactions else { throw FinanceDataError.tooManyTransactions }
        var output: [FinanceTransaction] = []
        var occurrences: [String: Int] = [:]
        var usedIDs = Set<UUID>()
        let iso = ISO8601DateFormatter()
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (offset, row) in rows.enumerated() {
            let line = offset + 2
            guard row.count == header.count else { throw CSVImportError.invalid("linha \(line) com colunas inconsistentes.") }
            func get(_ key: String, fallback: String = "") -> String {
                guard let i = indices[key] else { return fallback }
                let value = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? fallback : value
            }
            let currency = get("currency", fallback: "BRL")
            guard currency == "BRL" else { throw CSVImportError.invalid("linha \(line): esta versão importa apenas BRL.") }
            guard let kind = TransactionKind(rawValue: get("kind")) else {
                throw CSVImportError.invalid("linha \(line): kind precisa ser income, expense ou transfer.")
            }
            let dateText = get("date")
            guard dateText.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil,
                  let date = fractionalISO.date(from: dateText) ?? iso.date(from: dateText) else {
                throw CSVImportError.invalid("linha \(line): use data ISO 8601 com fuso, como 2026-10-31T12:30:00-03:00.")
            }
            let amount: Int64
            do { amount = try Money.parseBRL(get("amount")) }
            catch { throw CSVImportError.invalid("linha \(line): valor positivo no formato 123,45; o tipo define entrada ou saída.") }
            let merchant = get("merchant")
            let category = get("category", fallback: "A categorizar")
            let account = get("account", fallback: "Importada")
            let note = get("note")
            let id: UUID
            if !get("id").isEmpty {
                guard let supplied = UUID(uuidString: get("id")) else {
                    throw CSVImportError.invalid("linha \(line): identificador inválido.")
                }
                id = supplied
            } else {
                // Length-delimited JSON fields prevent separator ambiguities. Repeated identical
                // rows get distinct occurrence IDs; importing the same file again is idempotent.
                let identity = [String(amount), currency, merchant, String(date.timeIntervalSince1970),
                                kind.rawValue, category, account, note]
                let canonical = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
                let occurrence = occurrences[canonical, default: 0]
                occurrences[canonical] = occurrence + 1
                var bytes = Array(SHA256.hash(data: Data(("financeiro.csv.v1:" + canonical + ":" + String(occurrence)).utf8)).prefix(16))
                bytes[6] = (bytes[6] & 0x0F) | 0x50
                bytes[8] = (bytes[8] & 0x3F) | 0x80
                id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            }
            guard usedIDs.insert(id).inserted else { throw CSVImportError.invalid("identificadores repetidos na linha \(line).") }
            let transaction = FinanceTransaction(id: id, amountMinor: amount, merchant: merchant, date: date,
                                                 kind: kind, category: category, account: account,
                                                 source: .imported, note: note)
            do { try transaction.validate() }
            catch { throw CSVImportError.invalid("linha \(line): \(error.localizedDescription)") }
            output.append(transaction)
        }
        guard !output.isEmpty else { throw CSVImportError.invalid("nenhum lançamento encontrado.") }
        return output
    }

    private static func fields(_ text: String, delimiter: Character) throws -> [[String]] {
        // Character iteration avoids splitting CRLF into an extra empty record.
        enum State { case plain, quoted, afterQuote }
        var state = State.plain
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        func finishRow() throws {
            row.append(field)
            field = ""
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
            row = []
            guard rows.count <= TransactionStore.maximumTransactions + 1 else {
                throw FinanceDataError.tooManyTransactions
            }
        }
        for character in text {
            switch state {
            case .quoted:
                if character == "\"" { state = .afterQuote }
                else { field.append(character) }
            case .afterQuote:
                if character == "\"" { field.append(character); state = .quoted }
                else if character == delimiter { row.append(field); field = ""; state = .plain }
                else if character.isNewline { try finishRow(); state = .plain }
                else { throw CSVImportError.invalid("caractere após aspas de fechamento.") }
            case .plain:
                if character == "\"" {
                    guard field.isEmpty else { throw CSVImportError.invalid("aspas dentro de campo sem escape.") }
                    state = .quoted
                } else if character == delimiter { row.append(field); field = "" }
                else if character.isNewline { try finishRow() }
                else { field.append(character) }
            }
        }
        guard state != .quoted else { throw CSVImportError.invalid("campo com aspas não foi fechado.") }
        if !field.isEmpty || !row.isEmpty { try finishRow() }
        return rows
    }
}
