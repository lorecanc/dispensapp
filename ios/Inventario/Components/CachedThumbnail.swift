import SwiftUI
import UIKit
import ImageIO

/// Miniatura con cache in memoria e downsampling via ImageIO.
///
/// Sostituisce `AsyncImage` nelle liste: l'immagine full-size viene scaricata
/// una sola volta e ridimensionata alla risoluzione di render già decodificata
/// in background, così lo scroll non riscarica né ridecodifica nulla.
/// Cache hit (es. rientro nella viewport) è istantanea.
struct CachedThumbnail: View {
    let url: URL?
    /// Ingombro della miniatura in punti: lato del quadrato con `.fill`, altezza
    /// massima con `.fit`. Usata anche per il budget di downsampling in pixel.
    let side: CGFloat
    var cornerRadius: CGFloat = 12
    /// `.fill`: crop alla cornice quadrata side×side (righe/liste).
    /// `.fit`: rapporto d'aspetto preservato, altezza max `side`, larghezza libera
    /// (dettaglio, come il vecchio AsyncImage).
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        framedContent
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Bordo solo sull'immagine caricata, coerente con la riga (crop quadrato).
                if image != nil, contentMode == .fill {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.pantryOat.opacity(0.6), lineWidth: 0.5)
                }
            }
            // .task(id:) annulla il caricamento precedente quando la vista
            // scompare o cambia url: niente download orfani durante lo scroll.
            .task(id: url) { await load() }
    }

    /// .fill impone il quadrato; .fit lascia la larghezza libera con altezza max side.
    @ViewBuilder
    private var framedContent: some View {
        if contentMode == .fill {
            content.frame(width: side, height: side)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: side)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if failed {
            Color.pantryOat.opacity(0.35)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.textSecondary)
                }
        } else {
            Color.pantryOat.opacity(0.25)
                .overlay {
                    ProgressView()
                        .tint(Color.pantryMoss)
                }
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            failed = false
            return
        }
        let maxPixelSize = side * displayScale
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)

        if let hit = ThumbnailMemoryCache.shared.image(for: key) {
            image = hit
            failed = false
            return
        }

        image = nil
        failed = false
        do {
            let loaded = try await ThumbnailLoader.load(url: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            ThumbnailMemoryCache.shared.store(loaded, for: key)
            image = loaded
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }

    /// Chiave che vincola l'entry anche alla risoluzione: evita che una
    /// miniatura da 56pt venga riusata (sfocata) per un render più grande.
    private static func cacheKey(for url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize.rounded()))"
    }
}

/// Cache in memoria delle miniature già decodificate. `NSCache` è thread-safe,
/// quindi la classe è Sendable in modo verificato; si auto-pulisce sotto
/// pressione di memoria.
private final class ThumbnailMemoryCache: @unchecked Sendable {
    static let shared = ThumbnailMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64 MB di pixel decodificati
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        cache.setObject(image, forKey: key as NSString, cost: Int(pixels * 4))
    }
}

/// Download + downsampling fuori dal main thread. `URLSession.shared` usa già
/// la `URLCache` condivisa (disco incluso) a costo zero, quindi qui serve solo
/// il percorso rapido in memoria per lo scroll.
private enum ThumbnailLoader {
    enum LoadError: Error { case decoding }

    nonisolated static func load(url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // Decodifica CPU-bound fuori dal MainActor, con priorità esplicita:
        // lavoro breve e scartabile, i guard nel chiamante evitano scritture obsolete.
        let downsampled = await Task.detached(priority: .userInitiated) {
            downsample(data: data, maxPixelSize: maxPixelSize)
        }.value
        guard let image = downsampled else {
            throw LoadError.decoding
        }
        return image
    }

    /// Riduce l'immagine durante la decodifica (ImageIO), senza mai caricare
    /// il bitmap full-size in memoria.
    nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true, // decodifica ora, in background
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize.rounded()
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}
