import SwiftUI

@main
struct InventarioApp: App {
    @State private var store = InventoryStore()
    @State private var pendingInviteToken: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onOpenURL { url in
                    if let token = Self.inviteToken(from: url) {
                        pendingInviteToken = token
                    } else {
                        pendingInviteToken = nil
                    }
                }
                .confirmationDialog(
                    "Unirti alla dispensa condivisa?",
                    isPresented: Binding(
                        get: { pendingInviteToken != nil },
                        set: { if !$0 { pendingInviteToken = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Unisciti") {
                        if let token = pendingInviteToken {
                            pendingInviteToken = nil
                            Task { await store.acceptInviteToken(token) }
                        }
                    }
                    Button("Annulla", role: .cancel) {
                        pendingInviteToken = nil
                    }
                } message: {
                    Text("La dispensa condivisa verrà aggiunta al tuo elenco.")
                }
        }
    }

    private static func isValidInviteToken(_ token: String) -> Bool {
        token.range(of: "^[A-Za-z0-9_-]{20,64}$", options: .regularExpression) != nil
    }

    private static func inviteToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "inventario" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let raw = components.queryItems?.first(where: { $0.name == "token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return isValidInviteToken(raw) ? raw : nil
        }
        guard let last = url.pathComponents.filter({ $0 != "/" }).last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !last.isEmpty, last != "invite" else { return nil }
        return isValidInviteToken(last) ? last : nil
    }
}
