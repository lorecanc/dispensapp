import SwiftUI

// MARK: - Terra HIG: Glass vs Material

/// Regola HIG per "Dispensa Terra"
///
/// **Glass** (Liquid Glass / `glassEffect` iOS 26+) SOLO su navigation layer:
/// - tabBar, toolbar, navigationBar
/// - sheet / popover chrome (header, grabber, detents)
/// - scanner overlay (cornice, overlay controlli)
/// Non usare Glass su content — rompe leggibilità e costo GPU.
///
/// **Material** (`Material.regular` / `thin` / `ultraThin`) SU content layer:
/// - card, list row, form section, tile prodotto
/// - background di pannelli informativi, badge contenitori
///
/// Deployment target iOS 17: Glass è disponibile solo da iOS 26.
/// Usare `glassIfAvailable` helper che fa fallback a `ultraThinMaterial` su iOS < 26.
/// Per card/list usare sempre Material tramite `pantryCardBackground`.
///
enum TerraHIG {
    /// Documenta dove applicare Glass.
    static let glassSurfaces: [String] = [
        "TabBar", "Toolbar", "NavigationBar", "SheetChrome", "ScannerOverlay"
    ]
    /// Documenta dove applicare Material.
    static let materialSurfaces: [String] = [
        "Card", "ListRow", "FormSection", "ProductTile", "InfoPanel"
    ]
}

// MARK: - Card / content helpers (Material)

extension View {
    /// Background per card/list content: Material + PantryLinen tint + bordo Terra.
    /// Usare su content layer, mai su navigation chrome.
    func pantryCardBackground(cornerRadius: CGFloat = 14) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                // Tint leggero con PantryLinen per coerenza Terra senza perdere blur.
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.pantryLinen.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.borderTerra, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
    }

    /// Background sottile per row/form section (meno elevazione).
    func pantryRowBackground(cornerRadius: CGFloat = 10) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.borderTerra, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Navigation helpers (Glass)

extension View {
    /// Applica Glass su navigation chrome se disponibile (iOS 26+), altrimenti ultraThinMaterial.
    /// Usare SOLO su toolbar/tabBar/sheet chrome/scanner overlay.
    @ViewBuilder
    func pantryGlassChrome(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            // Su iOS 26+ usa il system glass. Fallback automatico se non disponibile.
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Toolbar glass: da applicare al contenitore toolbar, non al content.
    @ViewBuilder
    func pantryToolbarGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive())
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
