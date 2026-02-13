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
            let pantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity
            )
            modelContext.insert(pantryItem)
            modelContext.delete(item)
        }
    }

    func addMissingIngredients(recipe: Recipe, pantryItems: [PantryItem], modelContext: ModelContext) {
        let pantryNames = Set(pantryItems.map { $0.name.lowercased() })
        for ingredient in recipe.ingredients {
            let ingredientLower = ingredient.lowercased()
            let isInPantry = pantryNames.contains { ingredientLower.contains($0) }
            if !isInPantry {
                let item = ShoppingListItem(name: ingredient)
                modelContext.insert(item)
            }
        }
    }
}
