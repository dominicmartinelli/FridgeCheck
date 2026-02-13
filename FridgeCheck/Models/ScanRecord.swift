import Foundation
import SwiftData

@Model
final class ScanRecord {
    var id: UUID
    var date: Date
    @Attribute(.externalStorage) var imageDataItems: [Data]
    var detectedIngredients: [String]
    var recipes: [Recipe]

    init(
        imageDataItems: [Data],
        detectedIngredients: [String] = [],
        recipes: [Recipe] = []
    ) {
        self.id = UUID()
        self.date = Date()
        self.imageDataItems = imageDataItems
        self.detectedIngredients = detectedIngredients
        self.recipes = recipes
    }
}
