import SwiftUI

/// Apply to every modal as well as the main screen so an already-open sheet
/// cannot reveal records when the app returns from the background.
@MainActor
struct PrivacyProtection: ViewModifier {
    @ObservedObject var model: AppModel
    @AppStorage("privacyLockEnabled") private var enabled = false
    @Environment(\.scenePhase) private var scenePhase
    private var hidden: Bool { enabled && (!model.unlocked || scenePhase != .active) }
    func body(content: Content) -> some View {
        ZStack {
            content.disabled(hidden).blur(radius: hidden ? 20 : 0).accessibilityHidden(hidden)
            if hidden {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(.mint)
                    Text("Financeiro protegido").font(.title2.bold())
                    Text("Autentique-se para visualizar seus registros.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let error = model.authenticationError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    Button("Desbloquear") { model.authenticate() }.buttonStyle(.borderedProminent).disabled(model.authenticating)
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
            }
        }
    }
}
