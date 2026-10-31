import AppIntents
import Foundation

enum IntentTransactionKind: String, AppEnum {
    case expense, income, transfer

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tipo de lançamento")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .expense: "Despesa", .income: "Receita", .transfer: "Transferência"
    ]
}

/// Only accepts fields explicitly supplied by the user's shortcut. No bank credentials or network.
struct RecordTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar transação"
    static var description = IntentDescription("Salva um lançamento em reais somente neste iPhone. Configure os campos no Atalhos. A data é a da execução se você não fornecer a data original.")
    static var openAppWhenRun = false
    // This write-only action can run while locked, after the first unlock following a reboot.
    // It does not expose balances, history or backup passwords to Siri/Shortcuts.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Valor em reais", description: "Número positivo com até duas casas decimais.")
    var amount: Double

    @Parameter(title: "Estabelecimento ou descrição")
    var merchant: String

    @Parameter(title: "Conta ou cartão", default: "Carteira")
    var account: String

    @Parameter(title: "Tipo", default: .expense)
    var kind: IntentTransactionKind

    @Parameter(title: "Categoria", default: "A categorizar")
    var category: String

    @Parameter(title: "Data original (opcional)")
    var transactionDate: Date?

    @Parameter(title: "Identificador único da transação (opcional)",
               description: "UUID estável para reenvios do mesmo evento. Sem ele, cada execução cria um lançamento.")
    var transactionID: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$amount) em \(\.$merchant)") {
            \.$account
            \.$kind
            \.$category
            \.$transactionDate
            \.$transactionID
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cents = try ShortcutAmount.minorUnits(amount)
        let id: UUID
        if let raw = transactionID, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = UUID(uuidString: raw) else { throw ShortcutError.invalidID }
            id = parsed
        } else {
            id = UUID()
        }
        let date = transactionDate ?? Date()
        let transaction = FinanceTransaction(
            id: id, amountMinor: cents, currency: "BRL", merchant: merchant,
            date: date, kind: TransactionKind(rawValue: kind.rawValue) ?? .expense,
            category: category, account: account, source: .shortcut,
            note: transactionDate == nil ? "Horário de registro pelo Atalhos; data original não informada." : ""
        )
        let inserted = try TransactionStore().add(transaction)
        guard inserted else {
            return .result(dialog: "Este identificador já estava salvo. Nenhum lançamento foi duplicado.")
        }
        if AutomaticBackup.shared.isConfigured {
            do {
                try AutomaticBackup.shared.run()
            } catch {
                // The transaction has already committed. Reporting it as a failed capture could
                // make Shortcuts retry and duplicate a real payment.
                return .result(dialog: "Lançamento salvo no iPhone. O backup precisa de atenção nos Ajustes do Financeiro.")
            }
        }
        return .result(dialog: "Lançamento salvo no iPhone.")
    }
}

struct FinanceiroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordTransactionIntent(),
            phrases: ["Registrar uma transação no \(.applicationName)"],
            shortTitle: "Registrar transação",
            systemImageName: "plus.circle"
        )
    }
}

enum ShortcutError: LocalizedError {
    case invalidAmount, invalidID
    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Informe um valor positivo em reais, com até duas casas decimais."
        case .invalidID: return "O identificador precisa ser um UUID válido ou ficar vazio."
        }
    }
}

enum ShortcutAmount {
    static func minorUnits(_ value: Double) throws -> Int64 {
        guard value.isFinite, value > 0 else { throw ShortcutError.invalidAmount }
        // Decimal conversion through the canonical decimal string avoids binary FP artifacts.
        guard let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            throw ShortcutError.invalidAmount
        }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard scaled == rounded, rounded <= Decimal(Int64.max), rounded > 0 else {
            throw ShortcutError.invalidAmount
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
