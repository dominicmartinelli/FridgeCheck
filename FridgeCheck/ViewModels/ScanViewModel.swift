import SwiftUI
import SwiftData

struct DetectedIngredient: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let estimatedQuantity: String
    var isSelected: Bool = true
}

@Observable
final class ScanViewModel {
    var capturedImage: UIImage?
    var detectedIngredients: [DetectedIngredient] = []
    var suggestedRecipes: [Recipe] = []
    var isAnalyzing = false
    var isGeneratingRecipes = false
    var errorMessage: String?
    var showError = false

    private let apiService = ClaudeAPIService()

    func analyzeImage(apiKey: String) async {
        guard let image = capturedImage else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            let results = try await apiService.analyzeImage(image, apiKey: apiKey)
            await MainActor.run {
                self.detectedIngredients = results.map {
                    DetectedIngredient(
                        name: $0.name,
                        category: $0.category,
                        estimatedQuantity: $0.estimatedQuantity
                    )
                }
                self.isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isAnalyzing = false
            }
        }
    }

    func generateRecipes(
        preferences: UserPreferences?,
        pantryItems: [PantryItem],
        apiKey: String
    ) async {
        let selectedIngredients = detectedIngredients.filter(\.isSelected).map(\.name)
        guard !selectedIngredients.isEmpty else { return }

        isGeneratingRecipes = true
        errorMessage = nil

        do {
            let results = try await apiService.generateRecipes(
                ingredients: selectedIngredients,
                dietaryRestrictions: preferences?.dietaryRestrictions ?? [],
                allergies: preferences?.allergies ?? [],
                cuisinePreferences: preferences?.cuisinePreferences ?? [],
                servingSize: preferences?.servingSize ?? 2,
                pantryItems: pantryItems.map(\.name),
                apiKey: apiKey
            )

            await MainActor.run {
                self.suggestedRecipes = results.map { result in
                    Recipe(
                        title: result.title,
                        summary: result.summary,
                        ingredients: result.ingredients,
                        steps: result.steps,
                        prepTime: result.prepTime,
                        cookTime: result.cookTime,
                        nutritionalInfo: result.nutritionalInfo,
                        cuisineType: result.cuisineType,
                        difficulty: result.difficulty,
                        sourceIngredients: selectedIngredients
                    )
                }
                self.isGeneratingRecipes = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isGeneratingRecipes = false
            }
        }
    }

    func toggleIngredient(_ ingredient: DetectedIngredient) {
        if let index = detectedIngredients.firstIndex(where: { $0.id == ingredient.id }) {
            detectedIngredients[index].isSelected.toggle()
        }
    }

    func addIngredientsToPantry(modelContext: ModelContext) {
        let selected = detectedIngredients.filter(\.isSelected)
        for ingredient in selected {
            let pantryItem = PantryItem(
                name: ingredient.name,
                category: ingredient.category,
                quantity: ingredient.estimatedQuantity
            )
            modelContext.insert(pantryItem)
        }
    }

    func saveScanRecord(modelContext: ModelContext) {
        guard let image = capturedImage,
              let imageData = image.jpegData(compressionQuality: 0.6) else { return }

        let record = ScanRecord(
            imageData: imageData,
            detectedIngredients: detectedIngredients.map(\.name),
            recipes: suggestedRecipes
        )
        modelContext.insert(record)
    }

    func reset() {
        capturedImage = nil
        detectedIngredients = []
        suggestedRecipes = []
        isAnalyzing = false
        isGeneratingRecipes = false
        errorMessage = nil
    }
}
