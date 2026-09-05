import SwiftUI
import UIKit

// Sheet inviti/membri: tutta la logica resta in InventoryStore.
struct InviteMembersSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            List {
                inviteSection
                membersSection
            }
            .navigationTitle("Membri dispensa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .task(id: store.selectedPantryId) {
                await store.fetchMembers(pantryId: store.selectedPantryId)
            }
            .onChange(of: store.inviteLink) { _, _ in didCopy = false }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Link invito: creazione owner-only (403 server-side se non owner).
    // Frasi oneste: chi ha il link può unirsi, scadenza 7 giorni.
    private var inviteSection: some View {
        Section {
            Text("Chi ha il link può unirsi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Il link scade tra 7 giorni.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if store.isInviteLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Operazione in corso…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    await store.createInvite(pantryId: store.selectedPantryId)
                    didCopy = false
                }
            } label: {
                Label("Crea link invito", systemImage: "link.badge.plus")
                    .frame(minHeight: 44)
            }
            .disabled(store.isInviteLoading)
            .accessibilityLabel("Crea link invito")
            .accessibilityHint("Crea un link: chi ha il link può unirsi, scade tra 7 giorni")
            if let link = store.inviteLink, let url = URL(string: link) {
                ShareLink(item: url) {
                    Label("Condividi invito", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Condividi invito")
                .accessibilityHint("Condividi il link: chi ha il link può unirsi")
                Button {
                    UIPasteboard.general.string = link
                    didCopy = true
                } label: {
                    Label("Copia link", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Copia link invito")
                .accessibilityHint("Copia il link negli appunti")
                if didCopy {
                    Label("Copiato negli appunti", systemImage: "checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let inviteError = store.inviteError {
                Text(inviteErrorText(inviteError))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Errore invito: \(inviteErrorText(inviteError))")
            }
        } header: {
            Text("Link invito")
        }
    }

    // Mapping onesto per contesto inviti, senza mai includere il token.
    private func inviteErrorText(_ error: APIError) -> String {
        switch error {
        case .http(let status, _):
            switch status {
            case 401, 403:
                return "Solo il proprietario può invitare o rimuovere persone."
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

    // PantryMember non espone member_token: rimozione UI impossibile, lista sola lettura.
    private var membersSection: some View {
        Section {
            if store.members.isEmpty {
                Text("Nessun membro oltre a te.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.members.enumerated()), id: \.offset) { _, member in
                    HStack {
                        Text(roleLabel(member.role))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(member.joinedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Lista membri")
                .accessibilityHint("Elenco dei membri in sola lettura")
            }
            Text("Solo il proprietario può rimuovere membri.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Membri")
        }
    }

    // Ruoli in chiaro per l'utente; fallback capitalized per ruoli sconosciuti.
    private func roleLabel(_ role: String) -> String {
        switch role {
        case "owner": return "Proprietario"
        case "editor": return "Collaboratore"
        default: return role.capitalized
        }
    }
}
