import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "com.fridgecheck.app", category: "FridgeCheckAPI")

struct IngredientResult: Codable {
    let name: String
    let category: String
    let estimatedQuantity: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? "Other"
        estimatedQuantity = (try? c.decode(String.self, forKey: .estimatedQuantity)) ?? ""
    }
}

struct RecipeResult: Codable {
    let title: String
    let summary: String
    let ingredients: [String]
    let steps: [String]
    let prepTime: Int
    let cookTime: Int
    let nutritionalInfo: String
    let cuisineType: String
    let difficulty: String
    let source: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        ingredients = (try? c.decode([String].self, forKey: .ingredients)) ?? []
        steps = (try? c.decode([String].self, forKey: .steps)) ?? []
        nutritionalInfo = (try? c.decode(String.self, forKey: .nutritionalInfo)) ?? ""
        cuisineType = (try? c.decode(String.self, forKey: .cuisineType)) ?? ""
        difficulty = (try? c.decode(String.self, forKey: .difficulty)) ?? "Medium"
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        if let i = try? c.decode(Int.self, forKey: .prepTime) {
            prepTime = i
        } else if let s = try? c.decode(String.self, forKey: .prepTime), let i = Int(s) {
            prepTime = i
        } else { prepTime = 0 }
        if let i = try? c.decode(Int.self, forKey: .cookTime) {
            cookTime = i
        } else if let s = try? c.decode(String.self, forKey: .cookTime), let i = Int(s) {
            cookTime = i
        } else { cookTime = 0 }
    }
}

private struct ScanResponse: Decodable { let ingredients: [IngredientResult] }
private struct RecipesResponse: Decodable { let recipes: [RecipeResult] }

private struct ScanRequest: Encodable { let images: [String] }

private struct RecipeRequest: Encodable {
    let ingredients: [String]
    let dietaryRestrictions: [String]
    let allergies: [String]
    let cuisinePreferences: [String]
    let servingSize: Int
    let pantryItems: [String]
}

private struct ServerError: Decodable {
    let error: String
    let limit: Int?
    let used: Int?
}

actor FridgeCheckAPIService {
    enum APIError: LocalizedError {
        case notSignedIn
        case sessionExpired
        case invalidImage
        case networkError(Error)
        case decodingError(String)
        case quotaExceeded(used: Int, limit: Int)
        case serverError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in to continue."
            case .sessionExpired: return "Your session has expired. Please sign in again."
            case .invalidImage: return "Could not process the image. Please try again."
            case .networkError(let err): return "Network error: \(err.localizedDescription)"
            case .decodingError(let msg): return "Failed to parse response: \(msg)"
            case .quotaExceeded(let used, let limit): return "Daily limit reached (\(used)/\(limit)). Limits use a rolling 24-hour window — try again later."
            case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
            }
        }
    }

    func analyzeImages(_ images: [UIImage], sessionToken: String) async throws -> [IngredientResult] {
        guard !sessionToken.isEmpty else { throw APIError.notSignedIn }
        guard !images.isEmpty else { throw APIError.invalidImage }

        var encoded: [String] = []
        encoded.reserveCapacity(images.count)
        for image in images {
            // ~1024px is plenty for ingredient recognition; image tokens scale
            // with pixel count, so this halves scan cost vs. 1536px.
            let resized = Self.resizeImage(image, maxDimension: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.6) else {
                throw APIError.invalidImage
            }
            encoded.append(data.base64EncodedString())
        }

        let body = try JSONEncoder().encode(ScanRequest(images: encoded))
        let data = try await post(path: "/v1/scan", body: body, sessionToken: sessionToken)
        do {
            return try JSONDecoder().decode(ScanResponse.self, from: data).ingredients
        } catch {
            logger.error("scan decode failed: \(error.localizedDescription)")
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    func generateRecipes(
        ingredients: [String],
        dietaryRestrictions: [String],
        allergies: [String],
        cuisinePreferences: [String],
        servingSize: Int,
        pantryItems: [String],
        sessionToken: String
    ) async throws -> [RecipeResult] {
        guard !sessionToken.isEmpty else { throw APIError.notSignedIn }

        let body = try JSONEncoder().encode(RecipeRequest(
            ingredients: ingredients,
            dietaryRestrictions: dietaryRestrictions,
            allergies: allergies,
            cuisinePreferences: cuisinePreferences,
            servingSize: servingSize,
            pantryItems: pantryItems
        ))
        let data = try await post(path: "/v1/recipes", body: body, sessionToken: sessionToken)
        do {
            return try JSONDecoder().decode(RecipesResponse.self, from: data).recipes
        } catch {
            logger.error("recipes decode failed: \(error.localizedDescription)")
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    func deleteAccount(sessionToken: String) async throws {
        guard !sessionToken.isEmpty else { throw APIError.notSignedIn }

        var request = URLRequest(
            url: AppConfig.serverURL.appendingPathComponent("/v1/me"),
            timeoutInterval: 60
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(-1, "No response")
        }
        if http.statusCode == 204 { return }
        if http.statusCode == 401 { throw APIError.sessionExpired }

        let parsed = try? JSONDecoder().decode(ServerError.self, from: data)
        let msg = parsed?.error ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw APIError.serverError(http.statusCode, msg)
    }

    private func post(path: String, body: Data, sessionToken: String) async throws -> Data {
        var request = URLRequest(
            url: AppConfig.serverURL.appendingPathComponent(path),
            timeoutInterval: 300
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(-1, "No response")
        }
        if http.statusCode == 200 { return data }
        if http.statusCode == 401 { throw APIError.sessionExpired }

        let parsed = try? JSONDecoder().decode(ServerError.self, from: data)

        if http.statusCode == 429, let p = parsed, let used = p.used, let limit = p.limit {
            throw APIError.quotaExceeded(used: used, limit: limit)
        }

        let msg = parsed?.error ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw APIError.serverError(http.statusCode, msg)
    }

    static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > maxDimension else { return image }

        let ratio = maxDimension / longestSide
        let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
