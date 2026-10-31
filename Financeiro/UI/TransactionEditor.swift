import SwiftUI

@MainActor
struct TransactionEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let existing: FinanceTransaction?
    @State private var amount: String
    @State private var merchant: String
    @State private var date: Date
    @State private var kind: TransactionKind
    @State private var category: String
    @State private var account: String
    @State private var note: String
    @State private var validationError: String?

    init(model: AppModel, existing: FinanceTransaction? = nil) {
        self.model = model
        self.existing = existing
        _amount = State(initialValue: existing.map { String($0.amountMinor / 100) + "," + String(format: "%02lld", $0.amountMinor % 100) } ?? "")
        _merchant = State(initialValue: existing?.merchant ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _kind = State(initialValue: existing?.kind ?? .expense)
        _category = State(initialValue: existing?.category ?? "")
        _account = State(initialValue: existing?.account ?? "Principal")
        _note = State(initialValue: existing?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Lançamento") {
                    Picker("Tipo", selection: $kind) { ForEach(TransactionKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    HStack {
                        Text(existing?.currency ?? "BRL").foregroundStyle(.secondary)
                        TextField("0,00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("Valor")
                    }
                    TextField("Descrição ou estabelecimento", text: $merchant).textInputAutocapitalization(.sentences)
                    DatePicker("Data", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    TextField("Categoria", text: $category).textInputAutocapitalization(.sentences)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(suggestions, id: \.self) { value in Button(value) { category = value }.buttonStyle(.bordered).font(.caption) } }
                        }
                    }
                    TextField("Nome da conta", text: $account).textInputAutocapitalization(.words)
                } header: { Text("Organização") } footer: { Text("Use um nome como Carteira, Conta principal ou Cartão. Esse nome organiza registros e não conecta uma conta bancária.") }
                Section("Observação (opcional)") { TextField("Acrescente um detalhe", text: $note, axis: .vertical).lineLimit(3...6) }
                if kind == .transfer {
                    Section { Text("Transferências não entram em receitas ou despesas. Este é um registro simples; descreva a origem e o destino na observação.").font(.footnote).foregroundStyle(.secondary) }
                }
                if let validationError { Section { Text(validationError).foregroundStyle(.red) } }
            }
            .navigationTitle(existing == nil ? "Novo lançamento" : "Editar lançamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).fontWeight(.semibold) }
            }
            .alert("Não foi possível salvar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        }.modifier(PrivacyProtection(model: model))
    }
    private var suggestions: [String] {
        let defaults = kind == .income ? ["Salário", "Freelance", "Outras receitas"] : ["Alimentação", "Transporte", "Moradia", "Saúde", "Lazer"]
        return Array(Set(defaults + model.transactions.map(\.category).filter { !$0.isEmpty })).sorted()
    }
    private func save() {
        do {
            let parsed = try Money.parseBRL(amount)
            guard parsed > 0 else { validationError = "Informe um valor maior que zero."; return }
            let description = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountName = account.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty, !accountName.isEmpty else { validationError = "Preencha a descrição e o nome da conta."; return }
            let transaction = FinanceTransaction(id: existing?.id ?? UUID(), amountMinor: parsed, currency: existing?.currency ?? "BRL", merchant: description, date: date, kind: kind, category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sem categoria" : category.trimmingCharacters(in: .whitespacesAndNewlines), account: accountName, source: existing?.source ?? .manual, note: note)
            if model.save(transaction, editing: existing != nil) { dismiss() }
        } catch { validationError = "Valor inválido. Use, por exemplo, 125,90. \(error.localizedDescription)" }
    }
}

@MainActor
struct TransactionDetail: View {
    @ObservedObject var model: AppModel
    let transactionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    private var transaction: FinanceTransaction? { model.transactions.first { $0.id == transactionID } }
    var body: some View {
        Group {
            if let value = transaction {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(value.kind.title, systemImage: value.kind.symbol).foregroundStyle(value.kind.tint)
                            Text(value.formattedAmount).font(.largeTitle.bold()).minimumScaleFactor(0.5)
                            Text(value.displayMerchant).font(.headline)
                        }.padding(.vertical, 12)
                    }
                    Section("Detalhes") {
                        LabeledContent("Data", value: value.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "pt_BR"))))
                        LabeledContent("Categoria", value: value.category)
                        LabeledContent("Conta", value: value.account)
                        LabeledContent("Origem", value: value.source.title)
                        LabeledContent("Moeda", value: value.currency)
                    }
                    if !value.note.isEmpty { Section("Observação") { Text(value.note) } }
                    Section { Button("Excluir lançamento", role: .destructive) { deleting = true } }
                }
                .toolbar { Button("Editar") { editing = true } }
                .sheet(isPresented: $editing) { TransactionEditor(model: model, existing: value) }
                .confirmationDialog("Excluir este lançamento?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Excluir", role: .destructive) { if model.delete(value) { dismiss() } }
                    Button("Cancelar", role: .cancel) {}
                } message: { Text("Esta ação remove o registro deste aparelho.") }
            } else { ContentUnavailableView("Lançamento indisponível", systemImage: "tray", description: Text("O registro pode ter sido excluído.")) }
        }.navigationTitle("Lançamento").navigationBarTitleDisplayMode(.inline)
    }
}
