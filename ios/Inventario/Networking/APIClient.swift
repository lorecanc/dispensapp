import Foundation

@MainActor
final class APIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .inventoryDate
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // MARK: - Scan

    func scan(barcode: String) async throws -> ScanResult {
        let url = APIConfig.baseURL.appending(path: "api/scan")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["barcode": barcode])

        let data = try await perform(request)
        return try decoder.decode(ScanResult.self, from: data)
    }

    // MARK: - Create from scan

    func create(
        barcode: String,
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        imageURL: String?,
        quantity: Int
    ) async throws -> InventoryItem {
        let url = APIConfig.baseURL.appending(path: "api/inventory")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any?] = [
            "barcode": barcode,
            "name": name,
            "brand": brand,
            "category": category,
            "image_url": imageURL,
            "quantity": quantity,
        ]
        if let expirationDate {
            body["expiration_date"] = Self.dateFormatter.string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try decoder.decode(InventoryItem.self, from: data)
    }

    // MARK: - Create manual

    func createManual(
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int
    ) async throws -> InventoryItem {
        let url = APIConfig.baseURL.appending(path: "api/inventory/manual")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any?] = [
            "name": name,
            "brand": brand,
            "category": category,
            "quantity": quantity,
        ]
        if let expirationDate {
            body["expiration_date"] = Self.dateFormatter.string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try decoder.decode(InventoryItem.self, from: data)
    }

    // MARK: - Update

    func update(
        id: Int,
        name: String? = nil,
        brand: String? = nil,
        expirationDate: Date? = nil,
        category: String? = nil,
        quantity: Int? = nil
    ) async throws -> InventoryItem {
        let url = APIConfig.baseURL.appending(path: "api/inventory/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any?] = [
            "name": name,
            "brand": brand,
            "category": category,
            "quantity": quantity,
        ]
        if let expirationDate {
            body["expiration_date"] = Self.dateFormatter.string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try decoder.decode(InventoryItem.self, from: data)
    }

    // MARK: - List

    func list() async throws -> [InventoryItem] {
        let url = APIConfig.baseURL.appending(path: "api/inventory")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await perform(request)
        return try decoder.decode([InventoryItem].self, from: data)
    }

    // MARK: - Delete

    func delete(id: Int) async throws {
        let url = APIConfig.baseURL.appending(path: "api/inventory/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            throw APIError.http(status: httpResponse.statusCode, message: nil)
        }
    }

    // MARK: - Export Markdown

    func exportMarkdown() async throws -> String {
        let url = APIConfig.baseURL.appending(path: "api/inventory/export")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw APIError.notFound
            }
            throw APIError.http(status: httpResponse.statusCode, message: nil)
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw APIError.decoding(DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Response is not valid UTF-8 text")
            ))
        }
        return markdown
    }

    // MARK: - Private

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw APIError.notFound
            }
            let body = (try? JSONDecoder().decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }

        return data
    }
}


