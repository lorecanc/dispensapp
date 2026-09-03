import SwiftUI

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.pantryLinen)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.pantryLinen)

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
                .accessibilityHint("Tocca per nascondere il messaggio di errore")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.statusExpired.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Errore: \(message)")
        .accessibilityHint("Avviso di errore")
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}

struct SuccessBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pantryLinen)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.pantryLinen)

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
                .accessibilityHint("Tocca per nascondere il messaggio di successo")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.statusFresh.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Successo: \(message)")
        .accessibilityHint("Avviso di successo")
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
