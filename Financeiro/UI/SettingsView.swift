import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication

extension UTType {
    static let financeiroBackup = UTType(exportedAs: "br.com.iancfreitas.financeiro.backup", conformingTo: .data)
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.financeiroBackup, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("privacyLockEnabled") private var privacyLockEnabled = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var restorePassword = ""
    @State private var automaticPassword = ""
    @State private var automaticConfirmation = ""
    @State private var exporting = false
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var importing = false
    @State private var importKind: ImportKind = .backup
    @State private var encryptedImport: Data?
    @State private var askingPassword = false
    @State private var review: ImportReview?
    @State private var pendingReview: ImportReview?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var working = false
    @State private var disablingBackup = false
    private enum ImportKind { case backup, csv, folder }
    private var allowedTypes: [UTType] {
        switch importKind { case .backup: return [.financeiroBackup, .data]; case .csv: return [.commaSeparatedText, .plainText]; case .folder: return [.folder] }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Privado, no seu aparelho", systemImage: "lock.shield").font(.headline)
                    Text("O app funciona sem conexão e não acessa suas contas bancárias nem lê notificações de outros apps.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Exigir autenticação ao abrir", isOn: Binding(
                        get: { privacyLockEnabled },
                        set: { enabled in
                            if enabled {
                                var authError: NSError?
                                guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                                    errorMessage = "Configure um código de desbloqueio nos Ajustes do iPhone antes de ativar esta proteção."
                                    return
                                }
                            }
                            privacyLockEnabled = enabled
                        }
                    ))
                } footer: { Text("Face ID, Touch ID ou código protegem a visualização no app. Atalhos podem continuar adicionando registros com o aparelho bloqueado. O código e a proteção de dados do iOS ajudam a proteger os arquivos locais.") }

                Section {
                    SecureField("Senha do backup (12 caracteres ou mais)", text: $password).textContentType(.newPassword)
                    SecureField("Confirmar senha", text: $confirmation).textContentType(.newPassword)
                    Button { createBackup() } label: { Label("Exportar backup criptografado", systemImage: "square.and.arrow.up") }.disabled(working || !validPassword(password, confirmation))
                } header: { Text("Backup manual") } footer: {
                    Text("Na tela de exportação, escolha uma pasta no iCloud Drive para guardar uma cópia. A exportação é manual. Guarde a senha: ela é necessária para restaurar e não pode ser recuperada pelo app.")
                }

                Section {
                    Text(model.backupStatus).font(.footnote).foregroundStyle(.secondary)
                    if let backupError = model.backupError { Text(backupError).font(.footnote).foregroundStyle(.orange) }
                    SecureField("Senha para o backup automático", text: $automaticPassword).textContentType(.newPassword)
                    SecureField("Confirmar senha", text: $automaticConfirmation).textContentType(.newPassword)
                    Button("Escolher pasta e ativar") { importKind = .folder; importing = true }.disabled(working || !validPassword(automaticPassword, automaticConfirmation))
                    if model.backupConfigured {
                        Button("Fazer backup agora") { model.requestBackup() }.disabled(working)
                        Button("Desativar backup automático", role: .destructive) { disablingBackup = true }
                    }
                } header: { Text("Backup automático em pasta") } footer: {
                    Text("Escolha uma pasta no iCloud Drive. O app grava uma cópia criptografada após alterações e ao voltar à tela; não executa continuamente quando fechado. O iOS cuida do envio ao iCloud. O status confirma a gravação na pasta, não a conclusão do envio. A senha fica no Chaves deste aparelho para permitir novas cópias.")
                }

                Section {
                    Button { importKind = .backup; importing = true } label: { Label("Restaurar backup", systemImage: "arrow.counterclockwise") }
                    Button { importKind = .csv; importing = true } label: { Label("Importar CSV", systemImage: "tablecells") }
                    Text("Você revisa os registros antes de importar. A importação acrescenta lançamentos e mantém os atuais. Um mesmo identificador não é importado duas vezes.").font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Trazer registros") } footer: { Text("Arquivos de até 20 MB. Um CSV importado novamente pode conter registros com novos identificadores; revise para evitar duplicações.") }

                Section("Como registrar") {
                    Label("Adicione registros pelo botão + ou pelos Atalhos da Apple.", systemImage: "plus.circle")
                    Text("Transferências são anotações e não entram no fluxo do mês. As contas são nomes que você define, sem conexão com o banco.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
            .overlay { if working { ProgressView("Preparando arquivo…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
            .disabled(working)
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .financeiroBackup, defaultFilename: "Financeiro-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result {
                case .success: successMessage = "Backup exportado. Guarde a senha em um local seguro."
                case .failure(let error): errorMessage = "Não foi possível exportar. \(error.localizedDescription)"
                }
                exportDocument = BackupDocument(data: Data())
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
                do { if let url = try result.get().first { try receive(url) } }
                catch { errorMessage = "Não foi possível abrir o arquivo. \(error.localizedDescription)" }
            }
            .sheet(isPresented: $askingPassword, onDismiss: {
                restorePassword = ""; encryptedImport = nil
                if let pendingReview { review = pendingReview; self.pendingReview = nil }
            }) { restoreSheet }
            .sheet(item: $review) { value in ImportReviewView(model: model, review: value) }
            .alert("Não foi possível concluir", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
            .alert("Backup", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) { Button("OK") { successMessage = nil } } message: { Text(successMessage ?? "") }
            .confirmationDialog("Desativar backup automático?", isPresented: $disablingBackup, titleVisibility: .visible) {
                Button("Desativar", role: .destructive) {
                    disableAutomatic()
                }
            } message: { Text("Os arquivos já criados permanecem na pasta. A senha usada para novas cópias será removida deste aparelho.") }
        }.modifier(PrivacyProtection(model: model))
    }
    private func validPassword(_ first: String, _ second: String) -> Bool {
        first.count >= 12 && first.utf8.count <= 1_024 && first == second
    }

    private func createBackup() {
        working = true
        let store = model.store
        let secret = password
        Task {
            let result: Result<Data, Error> = await Task.detached(priority: .userInitiated) {
                Result { try BackupService.encrypt(transactions: store.all(), password: secret) }
            }.value
            working = false
            switch result {
            case .success(let data): exportDocument = BackupDocument(data: data); exporting = true; password = ""; confirmation = ""
            case .failure(let error): errorMessage = "Não foi possível criar o backup. \(error.localizedDescription)"
            }
        }
    }
    private func configureAutomatic(_ url: URL) {
        let secret = automaticPassword
        working = true
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do { try AutomaticBackup.shared.configure(folder: url, password: secret); return nil }
                catch { return error.localizedDescription }
            }.value
            working = false
            if let failure { errorMessage = "Não foi possível configurar a pasta. \(failure)" }
            else {
                automaticPassword = ""; automaticConfirmation = ""
                model.requestBackup()
            }
        }
    }
    private func disableAutomatic() {
        working = true
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do { try AutomaticBackup.shared.disable(); return nil }
                catch { return error.localizedDescription }
            }.value
            working = false
            if let failure { errorMessage = "Não foi possível concluir a desativação. \(failure)" }
            model.requestBackup()
        }
    }
    private func receive(_ url: URL) throws {
        if importKind == .folder {
            configureAutomatic(url)
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try limitedData(url)
        switch importKind {
        case .backup: encryptedImport = data; askingPassword = true
        case .csv:
            guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidEncoding }
            review = ImportReview(transactions: try CSVImporter.parse(text), title: "Revisar CSV")
        case .folder: break
        }
    }
    private func limitedData(_ url: URL) throws -> Data {
        let maximum = 20 * 1024 * 1024
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let size, size > maximum { throw ImportError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count + chunk.count <= maximum else { throw ImportError.tooLarge }
            data.append(chunk)
        }
        return data
    }
    private var restoreSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Senha do backup", text: $restorePassword)
                    Text("A senha é a mesma usada ao exportar este arquivo. Ela não pode ser recuperada.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Descriptografar e revisar") { decryptBackup() }.disabled(restorePassword.isEmpty || working)
                if working { ProgressView("Abrindo backup…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }.navigationTitle("Abrir backup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { askingPassword = false } } }
        }.interactiveDismissDisabled(working).modifier(PrivacyProtection(model: model))
    }
    private func decryptBackup() {
        guard let data = encryptedImport else { return }
        let secret = restorePassword
        working = true
        errorMessage = nil
        Task {
            let result: Result<[FinanceTransaction], Error> = await Task.detached(priority: .userInitiated) {
                Result { try BackupService.decrypt(data: data, password: secret) }
            }.value
            working = false
            switch result {
            case .success(let values):
                pendingReview = ImportReview(transactions: values, title: "Revisar restauração")
                askingPassword = false
            case .failure(let error): errorMessage = "Não foi possível abrir: senha incorreta ou arquivo inválido. \(error.localizedDescription)"
            }
        }
    }
    private enum ImportError: LocalizedError {
        case tooLarge, invalidEncoding
        var errorDescription: String? { self == .tooLarge ? "O arquivo excede o limite de 20 MB." : "O CSV precisa estar no formato de texto UTF-8." }
    }
}

struct ImportReview: Identifiable {
    let id = UUID()
    let transactions: [FinanceTransaction]
    let title: String
}

@MainActor
struct ImportReviewView: View {
    @ObservedObject var model: AppModel
    let review: ImportReview
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var importedMessage: String?
    private var existingIDs: Set<UUID> { Set(model.transactions.map(\.id)) }
    private var duplicateCount: Int { review.transactions.filter { existingIDs.contains($0.id) }.count }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(review.transactions.count) lançamento(s) no arquivo").font(.headline)
                    if duplicateCount > 0 { Text("\(duplicateCount) registro(s) já existente(s) serão ignorados pelo identificador.").font(.footnote) }
                    Text("Confira valores, datas e contas. Os registros atuais serão mantidos.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Prévia dos primeiros 100") {
                    ForEach(Array(review.transactions.prefix(100).enumerated()), id: \.offset) { _, value in TransactionRow(transaction: value).listRowInsets(EdgeInsets()) }
                }
                if review.transactions.count > 100 { Text("A importação inclui todos os \(review.transactions.count) registros; a prévia exibe os primeiros 100.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle(review.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Importar") { confirming = true }.disabled(review.transactions.isEmpty) }
                }
                .confirmationDialog("Adicionar estes lançamentos?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Adicionar e manter os atuais") {
                        if model.merge(review.transactions) {
                            importedMessage = model.notice ?? "Lançamentos importados."
                            model.notice = nil
                        }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: { Text("Confira possíveis duplicações antes de confirmar. Lançamentos com identificadores novos serão adicionados.") }
                .alert("Importação concluída", isPresented: Binding(get: { importedMessage != nil }, set: { if !$0 { importedMessage = nil } })) {
                    Button("Concluir") { importedMessage = nil; dismiss() }
                } message: { Text(importedMessage ?? "") }
                .alert("Não foi possível importar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        }.modifier(PrivacyProtection(model: model))
    }
}
