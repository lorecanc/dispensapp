import SwiftUI

// MARK: - PantryTone

/// Tono visivo delle sezioni dispensa, mappato sui token palette esistenti.
enum PantryTone: CaseIterable {
    case ok
    case soon
    case expired
    case neutral

    /// Accento pieno del tono; fill/bordi derivano da questo con opacity.
    var accent: Color {
        switch self {
        case .ok: .statusFresh
        case .soon: .statusSoon
        case .expired: .statusExpired
        case .neutral: .pantryMoss
        }
    }

    /// Nome parlato per l'accessibilityLabel.
    var accessibilityName: String {
        switch self {
        case .ok: "freschi"
        case .soon: "in scadenza"
        case .expired: "scaduti"
        case .neutral: "neutri"
        }
    }
}

// MARK: - PantryDisclosureGroup

/// Sezione espandibile della dispensa con identità di tono unificata.
/// Header in Material thin, capsule count sullo stesso `tone.accent`.
struct PantryDisclosureGroup<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    let tone: PantryTone
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        icon: String,
        count: Int,
        tone: PantryTone,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.tone = tone
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: animatedBinding) {
            content()
        } label: {
            header
        }
        // Unico tint del component: colora il chevron di sistema.
        .tint(tone.accent)
        // Animazione scoped, disattivata con Reduce Motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isExpanded)
    }

    /// Binding che anima il toggle senza intercettare il tap.
    private var animatedBinding: Binding<Bool> {
        Binding(
            get: { isExpanded },
            set: { newValue in
                if reduceMotion {
                    isExpanded = newValue
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isExpanded = newValue
                    }
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.accent)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(tone.accent.opacity(0.14))
                        .overlay(
                            Capsule()
                                .fill(.thinMaterial)
                                .opacity(0.35)
                        )
                }
                .overlay(
                    Capsule()
                        .strokeBorder(tone.accent.opacity(0.28), lineWidth: 0.5)
                )
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .pantryRowBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) prodotti, \(tone.accessibilityName)")
        .accessibilityValue(isExpanded ? "espanso" : "compresso")
        .accessibilityHint(isExpanded ? "Tocca per comprimere" : "Tocca per espandere")
        .accessibilityExpandedState(isExpanded)
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
