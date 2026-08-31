import SwiftUI

// MARK: - Terra "Dispensa Terra" Palette

/// Asset Catalog palette "Dispensa Terra".
/// Each color defines Light / Dark (and High Contrast placeholder) variants in srgb.
///
/// | Token             | Light     | Dark      |
/// |-------------------|-----------|-----------|
/// | PantryMoss        | #6B7E5B   | #A8C09A   |
/// | PantryTerracotta  | #C17A56   | #E8A07A   |
/// | PantryCream       | #F7F3EC   | #1E1E1C   |
/// | PantryLinen       | #FFFFFF   | #2C2C2E   |
/// | PantryEspresso    | #2B241E   | #F5F1E8   |
/// | PantryStone       | #8A827A   | #A8A29A   |
/// | PantryOat         | #E8E0D3   | #3A3632   |
/// | StatusFresh       | #5A8F5E   | #7BC080   |
/// | StatusSoon        | #C99A3A   | #E6B84A   |
/// | StatusExpired     | #B95C4A   | #E07A65   |
extension Color {
    // Raw palette — 1:1 with Assets.xcassets Color Sets
    static let pantryMoss = Color("PantryMoss")
    static let pantryTerracotta = Color("PantryTerracotta")
    static let pantryCream = Color("PantryCream")
    static let pantryLinen = Color("PantryLinen")
    static let pantryEspresso = Color("PantryEspresso")
    static let pantryStone = Color("PantryStone")
    static let pantryOat = Color("PantryOat")
    static let statusFresh = Color("StatusFresh")
    static let statusSoon = Color("StatusSoon")
    static let statusExpired = Color("StatusExpired")

    // Semantic tokens — stable aliases for app code
    /// Page / screen background (cream in light, near-black in dark).
    static let appBackground = Color("PantryCream")
    /// Surface for cards, sheets content, list rows (white / dark gray).
    static let surface = Color("PantryLinen")
    /// Secondary surface / section background, separators (oat).
    static let surfaceSecondary = Color("PantryOat")
    /// Primary text (espresso / light cream).
    static let textPrimary = Color("PantryEspresso")
    /// Secondary text / captions (stone).
    static let textSecondary = Color("PantryStone")
    /// Primary accent for CTAs, selection, active states (moss).
    static let accentTerra = Color("PantryMoss")
    /// Secondary accent for highlights, badges (terracotta).
    static let accentTerraSecondary = Color("PantryTerracotta")
    /// Subtle border / divider derived from stone with opacity.
    static var borderTerra: Color { Color.pantryStone.opacity(0.25) }
}
