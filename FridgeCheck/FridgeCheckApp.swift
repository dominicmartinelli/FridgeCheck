import SwiftUI
import SwiftData

@main
struct FridgeCheckApp: App {
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    MainTabView()
                } else {
                    SignInView()
                }
            }
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
