import SwiftUI
import SwiftData

@Observable
final class ShoppingListViewModel {
    var newItemName = ""
    var newItemQuantity = ""
    var newItemCategory = "Other"

    func groupedItems(_ items: [ShoppingListItem]) -> [(String, [ShoppingListItem])] {
        let grouped = Dictionary(grouping: items) { $0.category }
        return grouped.sorted { $0.key < $1.key }
    }

    func toggleItem(_ item: ShoppingListItem) {
        item.isChecked.toggle()
    }

    func addItem(modelContext: ModelContext) {
        guard !newItemName.isEmpty else { return }
        let item = ShoppingListItem(
            name: newItemName,
            quantity: newItemQuantity,
            category: newItemCategory
        )
        modelContext.insert(item)
        newItemName = ""
        newItemQuantity = ""
        newItemCategory = "Other"
    }

    func deleteItem(_ item: ShoppingListItem, modelContext: ModelContext) {
        modelContext.delete(item)
    }

    func clearCheckedItems(from items: [ShoppingListItem], modelContext: ModelContext) {
        for item in items where item.isChecked {
            modelContext.delete(item)
        }
    }

    func addCheckedItemsToPantry(from items: [ShoppingListItem], modelContext: ModelContext) {
        for item in items where item.isChecked {
            PantryItem.upsert(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                in: modelContext
            )
            modelContext.delete(item)
        }
    }

    func addMissingIngredients(recipe: Recipe, pantryItems: [PantryItem], modelContext: ModelContext) {
        let pantryWordSets = pantryItems.map { Self.words(of: $0.name) }
        for ingredient in recipe.ingredients {
            let ingredientWords = Self.words(of: ingredient)
            // Match on whole words so pantry "egg" doesn't swallow "eggplant":
            // a pantry item counts when all of its words appear in the
            // ingredient text (e.g. "olive oil" matches "2 tbsp olive oil").
            let isInPantry = pantryWordSets.contains { pantryWords in
                !pantryWords.isEmpty && pantryWords.isSubset(of: ingredientWords)
            }
            if !isInPantry {
                let item = ShoppingListItem(name: ingredient)
                modelContext.insert(item)
            }
        }
    }

    private static func words(of text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }
}
