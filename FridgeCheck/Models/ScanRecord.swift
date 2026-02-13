import Foundation
import SwiftData

@Model
final class ScanRecord {
    var id: UUID
    var date: Date
    @Attribute(.externalStorage) var imageData: Data
    var detectedIngredients: [String]
    var recipes: [Recipe]

    init(
        imageData: Data,
        detectedIngredients: [String] = [],
        recipes: [Recipe] = []
    ) {
        self.id = UUID()
        self.date = Date()
        self.imageData = imageData
        self.detectedIngredients = detectedIngredients
        self.recipes = recipes
    }
}
