import SwiftUI
import SwiftData

@Observable
final class PantryViewModel {
    var searchText = ""
    var selectedCategory = "All"

    let categories = ["All"] + String.ingredientCategories

    func filteredItems(_ items: [PantryItem]) -> [PantryItem] {
        var result = items

        if selectedCategory != "All" {
            result = result.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    func groupedItems(_ items: [PantryItem]) -> [(String, [PantryItem])] {
        let filtered = filteredItems(items)
        let grouped = Dictionary(grouping: filtered) { $0.category }
        return grouped.sorted { $0.key < $1.key }
    }

    func deleteItem(_ item: PantryItem, modelContext: ModelContext) {
        modelContext.delete(item)
    }

    func addToShoppingList(_ item: PantryItem, modelContext: ModelContext) {
        let shoppingItem = ShoppingListItem(
            name: item.name,
            quantity: item.quantity,
            category: item.category
        )
        modelContext.insert(shoppingItem)
    }

    func expiryWarningItems(_ items: [PantryItem]) -> [PantryItem] {
        items.filter { $0.isExpiringSoon || $0.isExpired }
    }
}
