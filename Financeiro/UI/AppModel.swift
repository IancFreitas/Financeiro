import SwiftUI
import LocalAuthentication

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var unlocked = false
    @Published var authenticating = false
    @Published var authenticationError: String?
    @Published var backupStatus = "Consultando backup automático…"
    @Published var backupConfigured = false
    private var authenticationContext: LAContext?
    private var authenticationGeneration = UUID()
    @Published var backupError: String?
    private var backupTask: Task<Void, Never>?
    private var backupPending = false
    let store: TransactionStore

    init(store: TransactionStore) {
        self.store = store
        refresh()
        requestBackup()
    }

    func refresh() {
        do { transactions = try store.all().sorted { $0.date > $1.date } }
        catch { errorMessage = "Não foi possível ler seus lançamentos. \(error.localizedDescription)" }
    }

    @discardableResult
    func save(_ transaction: FinanceTransaction, editing: Bool) -> Bool {
        do {
            if editing { try store.update(transaction) }
            else if try !store.add(transaction) { notice = "Este lançamento já está salvo." }
            refresh()
            requestBackup()
            return true
        } catch {
            errorMessage = "Não foi possível salvar. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func delete(_ transaction: FinanceTransaction) -> Bool {
        do { try store.delete(id: transaction.id); refresh(); requestBackup(); return true }
        catch { errorMessage = "Não foi possível excluir. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func merge(_ values: [FinanceTransaction]) -> Bool {
        do {
            let added = try store.merge(values)
            refresh()
            requestBackup()
            notice = "\(added) lançamento(s) adicionado(s). Registros com o mesmo identificador foram ignorados."
            return true
        } catch {
            errorMessage = "Não foi possível importar. \(error.localizedDescription)"
            return false
        }
    }
    func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        authenticationError = nil
        let generation = authenticationGeneration
        let context = LAContext()
        authenticationContext = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = "Autenticação indisponível. Configure um código nos Ajustes do iPhone para ativar esta proteção."
            authenticating = false
            errorMessage = authenticationError
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Acessar seus lançamentos financeiros") { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.authenticationGeneration == generation else { return }
                self.authenticating = false
                self.unlocked = success
                if !success { self.authenticationError = error?.localizedDescription ?? "Não foi possível autenticar. Tente novamente." }
            }
        }
    }

    func lock() {
        authenticationGeneration = UUID()
        authenticationContext?.invalidate()
        authenticationContext = nil
        authenticating = false
        unlocked = false
    }

    func requestBackup() {
        guard backupTask == nil else { backupPending = true; return }
        backupTask = Task {
            let outcome: (String?, String, Bool) = await Task.detached(priority: .utility) {
                var failure: String?
                do { try AutomaticBackup.shared.run() }
                catch { failure = error.localizedDescription }
                return (failure, AutomaticBackup.shared.statusDescription, AutomaticBackup.shared.isConfigured)
            }.value
            backupStatus = outcome.1
            backupConfigured = outcome.2
            backupError = outcome.0.map { "Os lançamentos estão salvos no aparelho, mas o backup na pasta falhou. \($0)" }
            backupTask = nil
            if backupPending { backupPending = false; requestBackup() }
        }
    }

}

extension TransactionKind {
    var title: String {
        switch self { case .income: return "Receita"; case .expense: return "Despesa"; case .transfer: return "Transferência" }
    }
    var symbol: String {
        switch self { case .income: return "arrow.down.left"; case .expense: return "arrow.up.right"; case .transfer: return "arrow.left.arrow.right" }
    }
    var tint: Color {
        switch self { case .income: return .mint; case .expense: return .orange; case .transfer: return .secondary }
    }
}

extension TransactionSource {
    var title: String {
        switch self { case .manual: return "Manual"; case .shortcut: return "Atalho"; case .imported: return "Importação" }
    }
}

extension FinanceTransaction {
    var displayMerchant: String { merchant.isEmpty ? kind.title : merchant }
    var formattedAmount: String {
        (kind == .expense ? "−" : kind == .income ? "+" : "") + Money.format(amountMinor, currency: currency)
    }
}
