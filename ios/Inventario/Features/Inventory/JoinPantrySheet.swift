import SwiftUI

// Sheet "Unisciti a una dispensa": accettazione invito via codice, flow estratto
// da InviteMembersSheet. Tutta la logica resta in InventoryStore.
struct JoinPantrySheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var showConfirm = false

    private var trimmedCode: String {
        codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                joinSection
            }
            .navigationTitle("Unisciti a una dispensa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .confirmationDialog(
                "Unirti alla dispensa condivisa?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Unisciti") {
                    Task {
                        await store.acceptInviteToken(trimmedCode)
                        codeInput = ""
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("La dispensa condivisa verrà aggiunta al tuo elenco.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Accettazione via codice incollato, con conferma. Codice mai persistito né loggato.
    // Campo e valore sanitizzato svuotati dopo l'uso.
    private var joinSection: some View {
        Section {
            TextField("Incolla qui il codice invito", text: $codeInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityLabel("Codice invito")
                .accessibilityHint("Incolla il codice che hai ricevuto, poi tocca Unisciti")
            Button {
                showConfirm = true
            } label: {
                Text("Unisciti")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pantryLinen)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background {
                Capsule()
                    .fill(Color.pantryMoss)
            }
            .disabled(trimmedCode.isEmpty || store.isInviteLoading)
            .accessibilityLabel("Unisciti")
            .accessibilityHint("Conferma e unisciti alla dispensa condivisa")
            if trimmedCode.isEmpty {
                Text("Incolla un codice valido per continuare.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let inviteError = store.inviteError {
                Text(inviteErrorText(inviteError))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Errore invito: \(inviteErrorText(inviteError))")
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    // Mapping onesto per contesto inviti, senza mai includere il codice.
    private func inviteErrorText(_ error: APIError) -> String {
        switch error {
        case .http(let status, _):
            switch status {
            case 401, 403:
                return "Codice non valido o scaduto. Chiedine uno nuovo."
            case 404, 410:
                return "Link scaduto, chiedine uno nuovo."
            case 409:
                return "Sei già membro di questa dispensa."
            default:
                return "Operazione non riuscita. Riprova."
            }
        case .notFound:
            return "Link scaduto, chiedine uno nuovo."
        case .offline:
            return "Nessuna connessione. Riprova."
        case .transport:
            return "Rete non disponibile. Riprova."
        case .invalidURL, .decoding:
            return "Operazione non riuscita. Riprova."
        }
    }
}
