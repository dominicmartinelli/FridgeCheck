import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "com.fridgecheck.app", category: "ClaudeAPI")

struct IngredientResult: Codable {
    let name: String
    let category: String
    let estimatedQuantity: String
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
}

struct AnalysisResponse: Codable {
    let ingredients: [IngredientResult]
}

struct RecipeSuggestionResponse: Codable {
    let recipes: [RecipeResult]
}

actor ClaudeAPIService {
    private let model = "claude-sonnet-4-5-20250929"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    enum APIError: LocalizedError {
        case noAPIKey
        case invalidImage
        case networkError(Error)
        case decodingError(String)
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Please add your Claude API key in Settings."
            case .invalidImage:
                return "Could not process the image. Please try again."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let message):
                return "Failed to parse response: \(message)"
            case .apiError(let message):
                return "API error: \(message)"
            }
        }
    }

    func analyzeImage(_ image: UIImage, apiKey: String) async throws -> [IngredientResult] {
        logger.info("Starting image analysis...")
        guard !apiKey.isEmpty else {
            logger.error("No API key set")
            throw APIError.noAPIKey
        }
        let resized = Self.resizeImage(image, maxDimension: 1536)
        guard let imageData = resized.jpegData(compressionQuality: 0.6) else { throw APIError.invalidImage }
        logger.debug("Image size: \(imageData.count) bytes (resized from \(Int(image.size.width))x\(Int(image.size.height)) to \(Int(resized.size.width))x\(Int(resized.size.height)))")

        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Analyze this image of a fridge/food items. Identify all visible food items and ingredients.

        Return your response as valid JSON with this exact structure:
        {
          "ingredients": [
            {
              "name": "item name",
              "category": "one of: Produce, Dairy, Meat, Seafood, Grains, Condiments, Beverages, Snacks, Frozen, Other",
              "estimatedQuantity": "estimated amount e.g. '2 pieces', '1 bag', '500ml'"
            }
          ]
        }

        Only return the JSON, no other text.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let responseData = try await makeRequest(body: body, apiKey: apiKey)
        let text = try extractText(from: responseData)
        logger.debug("Raw API response text: \(text)")
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Could not convert response to data")
            throw APIError.decodingError("Invalid response text")
        }

        do {
            let response = try JSONDecoder().decode(AnalysisResponse.self, from: jsonData)
            logger.info("Successfully parsed \(response.ingredients.count) ingredients")
            return response.ingredients
        } catch {
            logger.error("JSON decoding failed: \(error.localizedDescription)\nJSON was: \(jsonString)")
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
        apiKey: String
    ) async throws -> [RecipeResult] {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        var promptParts = [
            "I have these ingredients available: \(ingredients.joined(separator: ", "))."
        ]

        if !pantryItems.isEmpty {
            promptParts.append("I also have these pantry staples: \(pantryItems.joined(separator: ", ")).")
        }
        if !dietaryRestrictions.isEmpty {
            promptParts.append("Dietary restrictions: \(dietaryRestrictions.joined(separator: ", ")).")
        }
        if !allergies.isEmpty {
            promptParts.append("Allergies (must avoid): \(allergies.joined(separator: ", ")).")
        }
        if !cuisinePreferences.isEmpty {
            promptParts.append("Preferred cuisines: \(cuisinePreferences.joined(separator: ", ")).")
        }
        promptParts.append("Serving size: \(servingSize) people.")

        promptParts.append("""

        Suggest 5 recipes I can make. For each recipe, provide detailed instructions.

        Return your response as valid JSON with this exact structure:
        {
          "recipes": [
            {
              "title": "Recipe Name",
              "summary": "Brief 1-2 sentence description",
              "ingredients": ["ingredient 1 with amount", "ingredient 2 with amount"],
              "steps": ["Step 1 instruction", "Step 2 instruction"],
              "prepTime": 15,
              "cookTime": 30,
              "nutritionalInfo": "Approx. 450 cal, 25g protein, 35g carbs, 18g fat per serving",
              "cuisineType": "Italian",
              "difficulty": "Easy"
            }
          ]
        }

        Only return the JSON, no other text.
        """)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": promptParts.joined(separator: "\n")
                ]
            ]
        ]

        let responseData = try await makeRequest(body: body, apiKey: apiKey)
        let text = try extractText(from: responseData)
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw APIError.decodingError("Invalid response text")
        }

        do {
            let response = try JSONDecoder().decode(RecipeSuggestionResponse.self, from: jsonData)
            return response.recipes
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func makeRequest(body: [String: Any], apiKey: String) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw APIError.apiError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("API response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    logger.error("API error (\(httpResponse.statusCode)): \(errorBody)")
                    throw APIError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
                }
            }

            return data
        } catch let error as APIError {
            throw error
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw APIError.decodingError("Unexpected response structure")
        }
        return text
    }

    private func extractJSON(from text: String) -> String {
        // Try to extract JSON from markdown code blocks or raw text
        if let range = text.range(of: "```json") {
            let afterMarker = text[range.upperBound...]
            if let endRange = afterMarker.range(of: "```") {
                return String(afterMarker[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let range = text.range(of: "```") {
            let afterMarker = text[range.upperBound...]
            if let endRange = afterMarker.range(of: "```") {
                return String(afterMarker[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Assume the whole text is JSON
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
