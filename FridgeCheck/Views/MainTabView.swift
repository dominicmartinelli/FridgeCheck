import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            PantryView()
                .tabItem {
                    Label("Pantry", systemImage: "refrigerator.fill")
                }

            CameraView()
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }

            MealPlanView()
                .tabItem {
                    Label("Meals", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.accentColor)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [
            UserPreferences.self, PantryItem.self, Recipe.self,
            ScanRecord.self, ShoppingListItem.self, MealPlan.self
        ], inMemory: true)
}
