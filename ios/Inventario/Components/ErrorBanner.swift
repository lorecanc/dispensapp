import SwiftUI

// MARK: - BannerView

struct BannerView: View {
    enum Style {
        case error
        case success

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var background: Color {
            switch self {
            case .error: return Color.statusExpired.opacity(0.9)
            case .success: return Color.statusFresh.opacity(0.92)
            }
        }

        // Nomi it-IT identici ai banner pre-unificazione.
        var kindLabel: String {
            switch self {
            case .error: return "Errore"
            case .success: return "Successo"
            }
        }

        var kindWord: String {
            switch self {
            case .error: return "errore"
            case .success: return "successo"
            }
        }
    }

    let message: String
    var style: Style
    /// Per errori non bloccanti: chiama onDismiss dopo ~4s con animazione.
    var autoDismiss: Bool = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style.icon)
                .foregroundStyle(Color.pantryLinen)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.pantryLinen)
                // Etichetta sul testo, non sul contenitore: il Button Chiudi deve
                // restare azionabile (con .combine VoiceOver lo appiattisce).
                .accessibilityLabel("\(style.kindLabel): \(message)")
                .accessibilityHint("Avviso di \(style.kindWord)")

            Spacer(minLength: 0)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.pantryLinen.opacity(0.85))
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Chiudi avviso")
                .accessibilityHint("Tocca per nascondere il messaggio di \(style.kindWord)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .dynamicTypeSize(.xSmall ... .accessibility2)
        .task(id: message) {
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            // Coerente con la transition di rimozione (.move + .opacity).
            withAnimation(.easeInOut(duration: 0.25)) {
                onDismiss?()
            }
        }
    }
}

// MARK: - OfflinePill

/// Indicatore offline discreto (pill), non invasivo. Wiring a carico delle view (T13).
struct OfflinePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text("Offline — dati non aggiornati")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.pantryOat.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline, dati non aggiornati")
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
