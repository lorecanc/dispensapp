import SwiftUI

struct SettingsView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var apiURL: String = APIConfig.baseURLString
    @State private var connectionStatus: ConnectionStatus?
    @State private var showExportShare = false

    private let client = APIClient()

    enum ConnectionStatus: Equatable {
        case testing
        case success
        case failure(String)

        var color: Color {
            switch self {
            case .testing: return .gray
            case .success: return .green
            case .failure: return .red
            }
        }

        var icon: String {
            switch self {
            case .testing: return "hourglass"
            case .success: return "checkmark.circle.fill"
            case .failure: return "xmark.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .testing: return "Verifica in corso..."
            case .success: return "Connessione riuscita"
            case .failure(let msg): return msg
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("URL API", text: $apiURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: apiURL) { _, newValue in
                            APIConfig.baseURLString = newValue
                            connectionStatus = nil
                        }

                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test connessione")
                            Spacer()
                            if let status = connectionStatus {
                                Image(systemName: status.icon)
                                    .foregroundStyle(status.color)
                            }
                        }
                    }
                }

                Section("Esportazione") {
                    ShareLink(
                        item: store.exportedMarkdown ?? "Nessun dato disponibile.",
                        subject: Text("Inventario Dispensa"),
                        message: Text("Ecco l'elenco dei prodotti in dispensa.")
                    ) {
                        Label("Condividi dispensa", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.exportedMarkdown == nil)

                    Button {
                        Task { await store.exportMarkdown() }
                    } label: {
                        HStack {
                            Text("Genera esportazione")
                            Spacer()
                            if store.exportedMarkdown != nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section("Informazioni") {
                    HStack {
                        Text("Versione")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { dismiss() }
                }
            }
        }
    }

    private func testConnection() async {
        connectionStatus = .testing
        do {
            _ = try await client.list()
            connectionStatus = .success
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }
}
