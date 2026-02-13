import SwiftUI
import SwiftData

@main
struct FridgeCheckApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [
            Ingredient.self,
            Recipe.self,
            PantryItem.self,
            ShoppingListItem.self,
            MealPlan.self,
            ScanRecord.self,
            UserPreferences.self
        ])
    }
}
