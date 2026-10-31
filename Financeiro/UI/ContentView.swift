import SwiftUI
import LocalAuthentication

@MainActor
struct ContentView: View {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("privacyLockEnabled") private var privacyLockEnabled = false
    @State private var month = Date()
    @State private var search = ""
    @State private var category = "Todas"
    @State private var adding = false
    @State private var settings = false
    private let calendar = Calendar.current

    init(store: TransactionStore) { _model = StateObject(wrappedValue: AppModel(store: store)) }

    private var monthValues: [FinanceTransaction] {
        model.transactions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var categories: [String] { ["Todas"] + Set(monthValues.map(\.category).filter { !$0.isEmpty }).sorted() }
    private var visibleValues: [FinanceTransaction] {
        monthValues.filter { value in
            (category == "Todas" || value.category == category) &&
            (search.isEmpty || "\(value.merchant) \(value.category) \(value.account) \(value.note)".localizedCaseInsensitiveContains(search))
        }
    }
    private var income: Decimal { total(.income) }
    private var expense: Decimal { total(.expense) }
    private func total(_ kind: TransactionKind) -> Decimal {
        monthValues.filter { $0.kind == kind && $0.currency == "BRL" }.reduce(Decimal(0)) { $0 + Decimal($1.amountMinor) }
    }
    private var flow: Decimal { income - expense }
    private func formatSummary(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        return formatter.string(from: NSDecimalNumber(decimal: amount / 100)) ?? "Valor indisponível"
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        monthSelector
                        summary
                        transactionsSection
                    }.padding(20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Financeiro")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { settings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Ajustes e backup")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel("Adicionar lançamento")
                    }
                }
                .searchable(text: $search, prompt: "Buscar descrição, conta ou categoria")
            }
            .tint(Color(red: 0.1, green: 0.45, blue: 0.32))
            .sheet(isPresented: $adding) { TransactionEditor(model: model) }
            .sheet(isPresented: $settings) { SettingsView(model: model) }
            .disabled(privacyLockEnabled && !model.unlocked)
            .blur(radius: privacyLockEnabled && !model.unlocked ? 18 : 0)
            .accessibilityHidden(privacyLockEnabled && !model.unlocked)

            if privacyLockEnabled && !model.unlocked {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 52)).foregroundStyle(.mint)
                    Text("Seus registros, protegidos").font(.title2.bold())
                    Text("Use o Face ID, Touch ID ou o código do aparelho para continuar.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if let error = model.authenticationError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    Button("Desbloquear", action: authenticate).buttonStyle(.borderedProminent).disabled(model.authenticating)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Financeiro", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .onAppear { if privacyLockEnabled { authenticate() } }
        .onChange(of: privacyLockEnabled) { _, enabled in if enabled { model.unlocked = false; authenticate() } else { model.unlocked = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.lock() }
            if phase == .active { model.refresh(); model.requestBackup(); if privacyLockEnabled && !model.unlocked { authenticate() } }
        }
        .modifier(PrivacyProtection(model: model))
        .onChange(of: month) { _, _ in category = "Todas" }
        .onChange(of: categories) { _, values in if !values.contains(category) { category = "Todas" } }
    }

    private var monthSelector: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").padding(10) }.accessibilityLabel("Mês anterior")
            Spacer()
            VStack(spacing: 3) {
                Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))).font(.headline).textCase(.uppercase)
                Button("Ir para este mês") { month = Date() }.font(.caption)
            }
            Spacer()
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").padding(10) }.accessibilityLabel("Próximo mês")
        }
    }
    private func moveMonth(_ amount: Int) { if let next = calendar.date(byAdding: .month, value: amount, to: month) { month = next } }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("FLUXO DO MÊS", systemImage: "chart.line.uptrend.xyaxis").font(.caption.weight(.semibold)).tracking(1.5)
            Text(formatSummary(flow)).font(.system(.largeTitle, design: .rounded, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
            HStack {
                summaryItem("Receitas", amount: income, symbol: "arrow.down.left", tint: .mint)
                Spacer(minLength: 16)
                summaryItem("Despesas", amount: expense, symbol: "arrow.up.right", tint: Color(red: 1, green: 0.76, blue: 0.52))
            }
            Text("Resultado dos lançamentos em reais. Transferências não entram no fluxo; este valor não é o saldo da sua conta.")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
            if monthValues.contains(where: { $0.currency != "BRL" }) {
                Text("Lançamentos em outras moedas aparecem na lista, sem conversão no resumo.").font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }.padding(24).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.08, green: 0.29, blue: 0.23), Color(red: 0.06, green: 0.20, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }
    private func summaryItem(_ title: String, amount: Decimal, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(tint)
            Text(formatSummary(amount)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Lançamentos").font(.title2.bold())
                Spacer()
                Menu {
                    Picker("Categoria", selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                } label: { Label(category, systemImage: "line.3.horizontal.decrease.circle").font(.subheadline).lineLimit(1) }
            }
            if visibleValues.isEmpty {
                ContentUnavailableView(search.isEmpty && category == "Todas" ? "Seu mês começa aqui" : "Nenhum resultado", systemImage: "tray", description: Text(search.isEmpty && category == "Todas" ? "Adicione uma receita ou despesa para acompanhar seu fluxo." : "Tente outra busca ou categoria."))
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                if monthValues.isEmpty { Button("Adicionar lançamento") { adding = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(visibleValues) { value in
                        NavigationLink { TransactionDetail(model: model, transactionID: value.id) } label: { TransactionRow(transaction: value) }.buttonStyle(.plain)
                    }
                }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            Text("Os dados ficam neste aparelho. Crie um backup criptografado em Ajustes para guardá-los em outro local.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func authenticate() { model.authenticate() }

}

@MainActor
struct TransactionRow: View {
    let transaction: FinanceTransaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.kind.symbol).font(.headline).foregroundStyle(transaction.kind.tint).frame(width: 40, height: 40).background(transaction.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.displayMerchant).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text("\(transaction.category.isEmpty ? "Sem categoria" : transaction.category) · \(transaction.account)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(transaction.formattedAmount).font(.subheadline.weight(.semibold)).foregroundStyle(transaction.kind == .expense ? Color.primary : transaction.kind.tint).lineLimit(1).minimumScaleFactor(0.65)
                Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).accessibilityElement(children: .combine)
    }
}
