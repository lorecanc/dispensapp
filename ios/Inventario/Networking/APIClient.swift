import Foundation

/// Sendable networking client — not isolated to MainActor so requests run off the main thread.
/// Callers hop to MainActor only when assigning results to UI state (e.g. InventoryStore).
final class APIClient: Sendable {
    static let shared = APIClient()

    private static let maxPhotoBytes = 5 * 1024 * 1024

    // Vincoli backend su off_category_tags (backend/schemas.py): oltre, 422.
    private static let maxOffTags = 50
    private static let maxOffTagLength = 200

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

    // DateFormatter/JSONDecoder/JSONEncoder sono usati in lettura dopo la
    // configurazione: condividerli è sicuro (DateFormatter è thread-safe da iOS 7).
    // Outbound yyyy-MM-dd: il Date viene da un DatePicker (mezzanotte locale).
    // Va reso nel fuso del dispositivo: in GMT gli utenti a est di UTC
    // spedirebbero il giorno-1. Solo outbound; l'inbound resta GMT.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .inventoryDate
        return decoder
    }()

    private static let encoder = JSONEncoder()

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
        request.httpBody = try Self.encoder.encode(["barcode": barcode])
        request.timeoutInterval = 10

        let data = try await perform(request)
        return try Self.decoder.decode(ScanResult.self, from: data)
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
        labels: String? = nil,
        genericName: String? = nil,
        comment: String? = nil,
        appUUID: String? = nil,
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
        if let labels, !labels.isEmpty { body["labels"] = labels }
        if let genericName, !genericName.isEmpty { body["generic_name"] = genericName }
        if let comment, !comment.isEmpty { body["comment"] = comment }
        if let appUUID, !appUUID.isEmpty { body["app_uuid"] = appUUID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        return try Self.decoder.decode(ContributeResult.self, from: data)
    }

    func uploadPhoto(
        code: String,
        imageData: Data,
        filename: String,
        mimeType: String,
        imagefield: String,
        consent: Bool
    ) async throws -> ContributeResult {
        // Fail-fast locale: evita 30s di upload per un file che il backend rifiuterebbe con 413.
        guard imageData.count <= Self.maxPhotoBytes else {
            throw APIError.http(status: 413, message: "Immagine troppo grande (max 5MB).")
        }
        let url = try resolvedBaseURL().appending(path: "api/scan/contribute/photo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField(name: "code", value: code)
        appendField(name: "imagefield", value: imagefield)
        appendField(name: "consent_cc_bysa", value: consent ? "true" : "false")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data = try await perform(request)
        return try Self.decoder.decode(ContributeResult.self, from: data)
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
        let body = try Self.inventoryBody(
            barcode: barcode, name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            imageURL: imageURL, quantity: quantity
        )
        return try await sendInventory(method: "POST", path: "api/inventory", body: body)
    }

    // MARK: - Create manual

    func createManual(
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int
    ) async throws -> InventoryItem {
        let body = try Self.inventoryBody(
            name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            quantity: quantity
        )
        return try await sendInventory(method: "POST", path: "api/inventory/manual", body: body)
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
        let body = try Self.inventoryBody(
            name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            quantity: quantity
        )
        return try await sendInventory(method: "PATCH", path: "api/inventory/\(id)", body: body)
    }

    // MARK: - List

    func list() async throws -> [InventoryItem] {
        let url = try resolvedBaseURL().appending(path: "api/inventory")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await perform(request)
        return try Self.decoder.decode([InventoryItem].self, from: data)
    }

    // MARK: - Delete

    func delete(id: Int) async throws {
        try await deleteItem(at: "api/inventory/\(id)")
    }

    // MARK: - Export Markdown

    func exportScoped(pantryId: Int) async throws -> String {
        try await fetchMarkdown(from: "api/pantries/\(pantryId)/inventory/export")
    }

    func exportMarkdown() async throws -> String {
        try await fetchMarkdown(from: "api/inventory/export")
    }

    // MARK: - Shopping Lists

    func listShoppingLists(pantryId: Int) async throws -> [ShoppingList] {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode([ShoppingList].self, from: data)
    }

    func createShoppingList(pantryId: Int, name: String) async throws -> ShoppingList {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let data = try await perform(request)
        return try Self.decoder.decode(ShoppingList.self, from: data)
    }

    func getShoppingList(pantryId: Int, listId: Int) async throws -> ShoppingList {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode(ShoppingList.self, from: data)
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
        return try Self.decoder.decode(ShoppingListItem.self, from: data)
    }

    func toggleShoppingItem(pantryId: Int, listId: Int, itemId: Int, checked: Bool) async throws -> ShoppingListItem {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)/items/\(itemId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["checked": checked])
        let data = try await perform(request)
        return try Self.decoder.decode(ShoppingListItem.self, from: data)
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
            let body = (try? Self.decoder.decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }
    }

    func deleteShoppingList(pantryId: Int, listId: Int) async throws {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/shopping-lists/\(listId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request = decorated(request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            let body = (try? Self.decoder.decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
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
            let body = (try? Self.decoder.decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw APIError.decoding(DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Response is not valid UTF-8 text")
            ))
        }
        return markdown
    }

    // MARK: - Suggestions

    func fetchSuggestions(q: String) async throws -> [Suggestion] {
        var comps = URLComponents(url: try resolvedBaseURL().appending(path: "api/suggestions"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = comps.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode([Suggestion].self, from: data)
    }

    // MARK: - Categories

    /// Registry backend di categorie, shelf life e comparti (GET /api/categories).
    func fetchCategories() async throws -> CategoriesResponse {
        let url = try resolvedBaseURL().appending(path: "api/categories")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode(CategoriesResponse.self, from: data)
    }

    // MARK: - Pantry auth

    // MARK: - Pantries (tipi file-scope in fondo al file)

    func listPantries() async throws -> [Pantry] {
        let url = try resolvedBaseURL().appending(path: "api/pantries")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode([Pantry].self, from: data)
    }

    func createPantry(name: String) async throws -> Pantry {
        let url = try resolvedBaseURL().appending(path: "api/pantries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let data = try await perform(request)
        return try Self.decoder.decode(Pantry.self, from: data)
    }

    func deletePantry(id: Int) async throws {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request = decorated(request)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            throw APIError.http(status: httpResponse.statusCode, message: nil)
        }
    }

    // Accetta invito: prova POST /invites/accept con body, fallback al path legacy.
    // Mai log del token.
    func acceptInvite(token: String) async throws -> Invite {
        do {
            let url = try resolvedBaseURL().appending(path: "api/invites/accept")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token])
            let data = try await perform(request)
            return try Self.decoder.decode(Invite.self, from: data)
        } catch {
            let isNotFound: Bool = {
                if let api = error as? APIError {
                    if case .notFound = api { return true }
                    if case .http(let status, _) = api, status == 404 { return true }
                }
                return false
            }()
            if !isNotFound { throw error }
            let url = try resolvedBaseURL().appending(path: "api/invites/\(token)/accept")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token])
            let data = try await perform(request)
            return try Self.decoder.decode(Invite.self, from: data)
        }
    }

    // Crea invito (owner-only server-side). Mai log del token.
    func createInvite(pantryId: Int) async throws -> Invite {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/invites")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:] as [String: String])
        let data = try await perform(request)
        return try Self.decoder.decode(Invite.self, from: data)
    }

    func listMembers(pantryId: Int) async throws -> [PantryMember] {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/members")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode([PantryMember].self, from: data)
    }

    // Mai log del token.
    func removeMember(pantryId: Int, memberToken: String) async throws {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/members/\(memberToken)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request = decorated(request)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            throw APIError.http(status: httpResponse.statusCode, message: nil)
        }
    }

    // MARK: - Inventory pantry-scoped

    func listScoped(pantryId: Int) async throws -> [InventoryItem] {
        let limit = 50
        var offset = 0
        var all: [InventoryItem] = []
        while true {
            var comps = URLComponents(
                url: try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/inventory"),
                resolvingAgainstBaseURL: false
            )!
            comps.queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            guard let url = comps.url else { throw APIError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let data = try await perform(request)
            let page = try Self.decoder.decode([InventoryItem].self, from: data)
            all.append(contentsOf: page)
            if page.count < limit { break }
            offset += limit
        }
        return all
    }

    func createScoped(
        pantryId: Int,
        barcode: String,
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        imageURL: String?,
        quantity: Int,
        offTags: [String]? = nil,
        storageLocation: String? = nil,
        source: String? = nil,
        productType: String? = nil
    ) async throws -> InventoryItem {
        let body = try Self.inventoryBody(
            barcode: barcode, name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            imageURL: imageURL, quantity: quantity,
            offTags: offTags, storageLocation: storageLocation,
            source: source, productType: productType
        )
        return try await sendInventory(
            method: "POST", path: "api/pantries/\(pantryId)/inventory", body: body
        )
    }

    func createManualScoped(
        pantryId: Int,
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int,
        storageLocation: String? = nil
    ) async throws -> InventoryItem {
        let body = try Self.inventoryBody(
            name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            quantity: quantity, storageLocation: storageLocation
        )
        return try await sendInventory(
            method: "POST", path: "api/pantries/\(pantryId)/inventory/manual", body: body
        )
    }

    func updateScoped(
        pantryId: Int,
        id: Int,
        name: String? = nil,
        brand: String? = nil,
        expirationDate: Date? = nil,
        category: String? = nil,
        quantity: Int? = nil
    ) async throws -> InventoryItem {
        let body = try Self.inventoryBody(
            name: name, brand: brand,
            expirationDate: expirationDate, category: category,
            quantity: quantity
        )
        return try await sendInventory(
            method: "PATCH", path: "api/pantries/\(pantryId)/inventory/\(id)", body: body
        )
    }

    func deleteScoped(pantryId: Int, id: Int) async throws {
        try await deleteItem(at: "api/pantries/\(pantryId)/inventory/\(id)")
    }

    // Consumo atomico server-side: 409 se quantità insufficiente.
    func consume(pantryId: Int, itemId: Int, delta: Int = 1, reason: String? = nil) async throws -> InventoryItem {
        let url = try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/inventory/\(itemId)/consume")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["delta": delta]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        return try Self.decoder.decode(InventoryItem.self, from: data)
    }

    func history(pantryId: Int, itemId: Int, limit: Int = 50) async throws -> [ConsumptionEvent] {
        var comps = URLComponents(
            url: try resolvedBaseURL().appending(path: "api/pantries/\(pantryId)/inventory/\(itemId)/history"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = comps.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try Self.decoder.decode([ConsumptionEvent].self, from: data)
    }

    private func decorated(_ request: URLRequest) -> URLRequest {
        var req = request
        // Tutte le /api/* richiedono X-Pantry-Token (auth sistemica, non solo /pantries/).
        if let path = req.url?.path, path.contains("/api/") {
            if req.value(forHTTPHeaderField: PantryToken.headerName) == nil {
                req.setValue(PantryToken.value, forHTTPHeaderField: PantryToken.headerName)
            }
        }
        return req
    }

    /// Body JSON per la famiglia create/createManual/update: valori null scartati.
    /// Internal (non private) per gli unit test @testable del payload.
    static func inventoryBody(
        barcode: String? = nil,
        name: String?,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        imageURL: String? = nil,
        quantity: Int?,
        offTags: [String]? = nil,
        storageLocation: String? = nil,
        source: String? = nil,
        productType: String? = nil
    ) throws -> Data {
        var body: [String: Any?] = [
            "barcode": barcode,
            "name": name,
            "brand": brand,
            "category": category,
            "image_url": imageURL,
            "quantity": quantity,
        ]
        if let expirationDate {
            body["expiration_date"] = dateFormatter.string(from: expirationDate)
        }
        // Campi additivi (T11): presenti nel body solo se valorizzati.
        if let offTags {
            // Il backend dà 422 su liste >50 o tag >200 char; le categorie_tags di
            // OFF portano l'intera catena antenati e possono superarli. OFF non
            // garantisce un ordine, quindi si scartano i tag troppo lunghi e si
            // tiene semplicemente il prefisso dei primi 50.
            let capped = offTags
                .filter { $0.count <= Self.maxOffTagLength }
                .prefix(Self.maxOffTags)
            if !capped.isEmpty { body["off_category_tags"] = Array(capped) }
        }
        if let storageLocation, !storageLocation.isEmpty { body["storage_location"] = storageLocation }
        // Campi additivi (T8c): presenti nel body solo se valorizzati.
        if let source, !source.isEmpty { body["source"] = source }
        if let productType, !productType.isEmpty { body["product_type"] = productType }
        return try JSONSerialization.data(
            withJSONObject: body.filter { $0.value != nil }.mapValues { $0! }
        )
    }

    /// POST/PATCH con body JSON che risponde con un InventoryItem.
    private func sendInventory(method: String, path: String, body: Data) async throws -> InventoryItem {
        let url = try resolvedBaseURL().appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await perform(request)
        return try Self.decoder.decode(InventoryItem.self, from: data)
    }

    /// DELETE che si aspetta 200/204.
    private func deleteItem(at path: String) async throws {
        let url = try resolvedBaseURL().appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request = decorated(request)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 { throw APIError.notFound }
            throw APIError.http(status: httpResponse.statusCode, message: nil)
        }
    }

    /// GET che risponde text/markdown.
    private func fetchMarkdown(from path: String) async throws -> String {
        let url = try resolvedBaseURL().appending(path: path)
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
            let body = (try? Self.decoder.decode([String: String].self, from: data)).flatMap { $0["detail"] ?? $0["message"] }
            throw APIError.http(status: httpResponse.statusCode, message: body)
        }

        return data
    }
}

// MARK: - Pantries (file-scope: condivisi con InventoryStore)

struct Pantry: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct Invite: Codable, Equatable, Sendable {
    let id: Int
    let pantryId: Int
    let token: String
    let status: String
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, token
        case pantryId = "pantry_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct PantryMember: Codable, Equatable, Sendable {
    let pantryId: Int
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case pantryId = "pantry_id"
        case joinedAt = "joined_at"
    }
}

struct ConsumptionEvent: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let pantryId: Int
    let itemId: Int?
    let nameSnapshot: String
    let barcode: String?
    let delta: Int
    let reason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, barcode, delta, reason
        case pantryId = "pantry_id"
        case itemId = "item_id"
        case nameSnapshot = "name_snapshot"
        case createdAt = "created_at"
    }
}

/// Risposta di GET /api/categories (backend/routes/categories.py).
/// Consumati sono `categories` (key/label/storage_location) e `compartmentMap` /
/// `storageLocationLabels`: gli altri campi restano opzionali, così l'evoluzione
/// del backend non invalida il decode.
struct CategoriesResponse: Codable, Equatable, Sendable {
    struct Category: Codable, Equatable, Sendable {
        let key: String
        let label: String
        let shelfLifeDays: Int?
        /// Nil quando la chiave non ha mappatura nei comparti.
        let compartment: String?
        /// Campo additivo (T9): "frigo"|"freezer"|"dispensa", nil su backend non
        /// aggiornati. `var` per non rompere i memberwise-init esistenti (T14).
        var storageLocation: String?

        enum CodingKeys: String, CodingKey {
            case key, label, compartment
            case shelfLifeDays = "shelf_life_days"
            case storageLocation = "storage_location"
        }
    }

    let categories: [Category]
    let defaultShelfLifeDays: Int?
    /// Chiave categoria -> etichetta IT.
    let labels: [String: String]?
    /// Comparti supermercato ordinati.
    let compartments: [String]?
    /// Chiave categoria -> comparto.
    let compartmentMap: [String: String]
    /// Campo additivo (T9): codice storage -> etichetta IT. Nil su backend non
    /// aggiornati. `var` per non rompere i memberwise-init esistenti (T14).
    var storageLocationLabels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case categories, labels, compartments
        case defaultShelfLifeDays = "default_shelf_life_days"
        case compartmentMap = "compartment_map"
        case storageLocationLabels = "storage_location_labels"
    }
}
