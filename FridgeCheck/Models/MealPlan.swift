import Foundation
import SwiftData

@Model
final class MealPlan {
    var id: UUID
    var date: Date
    var mealType: String
    var recipe: Recipe?

    init(
        date: Date,
        mealType: String,
        recipe: Recipe? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.mealType = mealType
        self.recipe = recipe
    }
}
