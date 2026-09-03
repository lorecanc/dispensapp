import Foundation

/// Sendable networking client — not isolated to MainActor so requests run off the main thread.
/// Callers hop to MainActor only when assigning results to UI state (e.g. InventoryStore).
final class APIClient: Sendable {
    static let shared = APIClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .inventoryDate
        return decoder
    }

    private static func makeDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }

    private func resolvedBaseURL() throws -> URL {
        guard let url = APIConfig.baseURL else { throw APIError.invalidURL }
        return url
    }

    // MARK: - Scan

    func scan(barcode: String) async throws -> ScanResult {
        print("[APIClient] POST /api/scan barcode:", barcode)
        let url = try resolvedBaseURL().appending(path: "api/scan")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["barcode": barcode])
        request.timeoutInterval = 10

        let data = try await perform(request)
        return try makeDecoder().decode(ScanResult.self, from: data)
    }

    // MARK: - Contribute to Open Food Facts (via backend)

    struct ContributeResult: Decodable, Sendable {
        let ok: Bool
        let code: String
        let message: String?
    }

    func contribute(
        code: String,
        productName: String?,
        brands: String?,
        quantity: String?,
        categories: String?,
        lang: String = "it",
        consent: Bool
    ) async throws -> ContributeResult {
        let url = try resolvedBaseURL().appending(path: "api/scan/contribute")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "code": code,
            "consent_cc_bysa": consent,
            "lang": lang,
        ]
        if let productName, !productName.isEmpty { body["product_name"] = productName }
        if let brands, !brands.isEmpty { body["brands"] = brands }
        if let quantity, !quantity.isEmpty { body["quantity"] = quantity }
        if let categories, !categories.isEmpty { body["categories"] = categories }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        return try makeDecoder().decode(ContributeResult.self, from: data)
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
        let url = try resolvedBaseURL().appending(path: "api/inventory")
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
            body["expiration_date"] = Self.makeDateFormatter().string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try makeDecoder().decode(InventoryItem.self, from: data)
    }

    // MARK: - Create manual

    func createManual(
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int
    ) async throws -> InventoryItem {
        let url = try resolvedBaseURL().appending(path: "api/inventory/manual")
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
            body["expiration_date"] = Self.makeDateFormatter().string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try makeDecoder().decode(InventoryItem.self, from: data)
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
        let url = try resolvedBaseURL().appending(path: "api/inventory/\(id)")
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
            body["expiration_date"] = Self.makeDateFormatter().string(from: expirationDate)
        }
        let filteredBody = body.filter { $0.value != nil }.mapValues { $0! }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

        let data = try await perform(request)
        return try makeDecoder().decode(InventoryItem.self, from: data)
    }

    // MARK: - List

    func list() async throws -> [InventoryItem] {
        let url = try resolvedBaseURL().appending(path: "api/inventory")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await perform(request)
        return try makeDecoder().decode([InventoryItem].self, from: data)
    }

    // MARK: - Delete

    func delete(id: Int) async throws {
        let url = try resolvedBaseURL().appending(path: "api/inventory/\(id)")
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
        let url = try resolvedBaseURL().appending(path: "api/inventory/export")
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

    // MARK: - Shopping Lists

    func listShoppingLists(pantryId: Int) async throws -> [ShoppingList] {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try makeDecoder().decode([ShoppingList].self, from: data)
    }

    func createShoppingList(pantryId: Int, name: String) async throws -> ShoppingList {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let data = try await perform(request)
        return try makeDecoder().decode(ShoppingList.self, from: data)
    }

    func getShoppingList(pantryId: Int, listId: Int) async throws -> ShoppingList {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try makeDecoder().decode(ShoppingList.self, from: data)
    }

    func addShoppingItem(pantryId: Int, listId: Int, name: String, quantity: Int, compartment: String?) async throws -> ShoppingListItem {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/items")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["name": name, "quantity": quantity]
        if let compartment, !compartment.isEmpty { body["compartment"] = compartment }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        return try makeDecoder().decode(ShoppingListItem.self, from: data)
    }

    func toggleShoppingItem(pantryId: Int, listId: Int, itemId: Int, checked: Bool) async throws -> ShoppingListItem {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/items/\(itemId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["checked": checked])
        let data = try await perform(request)
        return try makeDecoder().decode(ShoppingListItem.self, from: data)
    }

    func deleteShoppingItem(pantryId: Int, listId: Int, itemId: Int) async throws {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/items/\(itemId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request = decorated(request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            let body = (try? JSONDecoder().decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }
    }

    func exportShoppingMarkdown(pantryId: Int, listId: Int) async throws -> String {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/export")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        request = decorated(request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            let body = (try? JSONDecoder().decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw APIError.decoding(DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Response is not valid UTF-8 text")
            ))
        }
        return markdown
    }

    func checkShoppingList(pantryId: Int, listId: Int) async throws -> [PantryCheckItem] {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/check")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        let decoded = try makeDecoder().decode(PantryCheckResponse.self, from: data)
        return decoded.items
    }

    // MARK: - Suggestions

    func fetchSuggestions(q: String) async throws -> [Suggestion] {
        var comps = URLComponents(url: try resolvedBaseURL().appending(path: "api/suggestions"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = comps.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try makeDecoder().decode([Suggestion].self, from: data)
    }

    // MARK: - Pantry auth

    private func decorated(_ request: URLRequest) -> URLRequest {
        var req = request
        if let path = req.url?.path, path.contains("/pantries/") || path.contains("/shopping-lists") {
            if req.value(forHTTPHeaderField: PantryToken.headerName) == nil {
                req.setValue(PantryToken.value, forHTTPHeaderField: PantryToken.headerName)
            }
        }
        return req
    }

    // MARK: - Private

    private func perform(_ request: URLRequest) async throws -> Data {
        let decoratedRequest = decorated(request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: decoratedRequest)
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
