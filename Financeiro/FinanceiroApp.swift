import SwiftUI

@main
struct FinanceiroApp: App {
    private let store: Result<TransactionStore, Error> = Result { try TransactionStore() }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let transactionStore):
                ContentView(store: transactionStore)
            case .failure:
                ContentUnavailableView(
                    "Não foi possível abrir seus dados",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Feche e abra o app após desbloquear o iPhone. Seus dados não serão substituídos. Se o erro persistir, preserve o app instalado e procure suporte antes de apagá-lo.")
                )
            }
        }
    }
}
