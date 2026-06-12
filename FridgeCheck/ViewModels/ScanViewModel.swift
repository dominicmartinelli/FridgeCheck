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
@MainActor
final class ScanViewModel {
    var capturedImages: [UIImage] = []
    var detectedIngredients: [DetectedIngredient] = []
    var suggestedRecipes: [Recipe] = []
    var isAnalyzing = false
    var isGeneratingRecipes = false
    var errorMessage: String?
    var showError = false

    private let apiService = FridgeCheckAPIService()

    func analyzeImages(sessionToken: String) async {
        guard !capturedImages.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            let results = try await apiService.analyzeImages(capturedImages, sessionToken: sessionToken)
            self.detectedIngredients = results.map {
                DetectedIngredient(
                    name: $0.name,
                    category: $0.category,
                    estimatedQuantity: $0.estimatedQuantity
                )
            }
            self.isAnalyzing = false
        } catch {
            handleAPIError(error)
            self.isAnalyzing = false
        }
    }

    func generateRecipes(
        preferences: UserPreferences?,
        pantryItems: [PantryItem],
        sessionToken: String
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
                sessionToken: sessionToken
            )

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
        } catch {
            handleAPIError(error)
            self.isGeneratingRecipes = false
        }
    }

    private func handleAPIError(_ error: Error) {
        // An expired session can only be fixed by signing in again — drop the
        // stale token so the app returns to the sign-in screen.
        if case FridgeCheckAPIService.APIError.sessionExpired = error {
            AuthService.shared.signOut()
        }
        errorMessage = error.localizedDescription
        showError = true
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

    func removeImage(at index: Int) {
        guard capturedImages.indices.contains(index) else { return }
        capturedImages.remove(at: index)
    }

    func saveScanRecord(modelContext: ModelContext) {
        guard !capturedImages.isEmpty else { return }

        let images = capturedImages
        Task {
            // Resize + JPEG-encode off the main actor: the originals are
            // full-resolution camera photos, and encoding them inline froze
            // the UI while writing multi-MB blobs into SwiftData.
            let imageDataItems = await Task.detached(priority: .userInitiated) {
                images.compactMap {
                    FridgeCheckAPIService.resizeImage($0, maxDimension: 1024)
                        .jpegData(compressionQuality: 0.6)
                }
            }.value
            guard !imageDataItems.isEmpty else { return }

            let record = ScanRecord(
                imageDataItems: imageDataItems,
                detectedIngredients: detectedIngredients.map(\.name),
                recipes: suggestedRecipes
            )
            modelContext.insert(record)
        }
    }

    func reset() {
        capturedImages = []
        detectedIngredients = []
        suggestedRecipes = []
        isAnalyzing = false
        isGeneratingRecipes = false
        errorMessage = nil
    }
}
