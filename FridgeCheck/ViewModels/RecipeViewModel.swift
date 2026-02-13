import SwiftUI
import SwiftData

@Observable
final class RecipeViewModel {
    var searchText = ""
    var selectedCuisine = "All"
    var selectedDifficulty = "All"

    let cuisines = ["All", "Italian", "Mexican", "Chinese", "Japanese", "Indian", "Thai", "French", "Mediterranean", "American", "Korean"]
    let difficulties = ["All", "Easy", "Medium", "Hard"]

    func filteredRecipes(_ recipes: [Recipe]) -> [Recipe] {
        var result = recipes

        if selectedCuisine != "All" {
            result = result.filter { $0.cuisineType == selectedCuisine }
        }

        if selectedDifficulty != "All" {
            result = result.filter { $0.difficulty == selectedDifficulty }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.summary.localizedCaseInsensitiveContains(searchText) ||
                $0.cuisineType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result.sorted { $0.dateCreated > $1.dateCreated }
    }

    func favoriteRecipes(_ recipes: [Recipe]) -> [Recipe] {
        recipes.filter(\.isFavorite).sorted { $0.dateCreated > $1.dateCreated }
    }

    func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
    }

    func deleteRecipe(_ recipe: Recipe, modelContext: ModelContext) {
        modelContext.delete(recipe)
    }

    func saveRecipe(_ recipe: Recipe, modelContext: ModelContext) {
        modelContext.insert(recipe)
    }
}
