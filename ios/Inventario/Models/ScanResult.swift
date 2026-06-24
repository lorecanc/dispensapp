import Foundation

struct ScanResult: Codable {
    let barcode: String
    let name: String?
    let brand: String?
    let categories: [String]
    let imageURL: String?
    let found: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, categories, found, message
        case imageURL = "image_url"
    }
}
