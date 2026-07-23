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
    private var savedRecord: ScanRecord?

    func analyzeImages(sessionToken: String, modelContext: ModelContext) async {
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
            autoSaveScanRecord(modelContext: modelContext)
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
                    sourceIngredients: selectedIngredients,
                    source: result.source
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
            PantryItem.upsert(
                name: ingredient.name,
                category: ingredient.category,
                quantity: ingredient.estimatedQuantity,
                in: modelContext
            )
        }
    }

    /// Pantry items that didn't appear anywhere in this scan — candidates for
    /// "used up" cleanup. Compares against every detected ingredient, selected
    /// or not: being seen in the fridge is what matters, not whether the user
    /// wants it in a recipe.
    func pantryItemsMissingFromScan(_ pantryItems: [PantryItem]) -> [PantryItem] {
        guard !detectedIngredients.isEmpty else { return [] }
        return PantryItem.itemsMissing(
            fromScan: detectedIngredients.map(\.name),
            in: pantryItems
        )
    }

    func removeImage(at index: Int) {
        guard capturedImages.indices.contains(index) else { return }
        capturedImages.remove(at: index)
    }

    // Saves the scan to history automatically after a successful analysis —
    // the old manual "Save Scan to History" button was easy to miss. One
    // record per scan session: re-analyzing (e.g. Try Again) updates the
    // existing record instead of duplicating it. Recipes are intentionally
    // not attached — linking them would force-insert every generated recipe
    // into the store; recipes persist only when the user saves them.
    private func autoSaveScanRecord(modelContext: ModelContext) {
        if let record = savedRecord {
            record.detectedIngredients = detectedIngredients.map(\.name)
            return
        }

        // Insert the record immediately (so the flag and history entry are
        // race-free) and backfill the image blobs once encoding finishes.
        let record = ScanRecord(
            imageDataItems: [],
            detectedIngredients: detectedIngredients.map(\.name)
        )
        modelContext.insert(record)
        savedRecord = record

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
            record.imageDataItems = imageDataItems
        }
    }

    func reset() {
        capturedImages = []
        detectedIngredients = []
        suggestedRecipes = []
        isAnalyzing = false
        isGeneratingRecipes = false
        errorMessage = nil
        savedRecord = nil
    }
}
