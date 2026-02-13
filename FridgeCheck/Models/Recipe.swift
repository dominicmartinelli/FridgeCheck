import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var title: String
    var summary: String
    var ingredients: [String]
    var steps: [String]
    var prepTime: Int
    var cookTime: Int
    var nutritionalInfo: String
    var cuisineType: String
    var difficulty: String
    var isFavorite: Bool
    var dateCreated: Date
    var sourceIngredients: [String]

    var totalTime: Int {
        prepTime + cookTime
    }

    init(
        title: String,
        summary: String,
        ingredients: [String] = [],
        steps: [String] = [],
        prepTime: Int = 0,
        cookTime: Int = 0,
        nutritionalInfo: String = "",
        cuisineType: String = "",
        difficulty: String = "Medium",
        isFavorite: Bool = false,
        sourceIngredients: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.ingredients = ingredients
        self.steps = steps
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.nutritionalInfo = nutritionalInfo
        self.cuisineType = cuisineType
        self.difficulty = difficulty
        self.isFavorite = isFavorite
        self.dateCreated = Date()
        self.sourceIngredients = sourceIngredients
    }
}
