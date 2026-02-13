import Foundation
import SwiftData

@Model
final class ShoppingListItem {
    var id: UUID
    var name: String
    var quantity: String
    var isChecked: Bool
    var category: String

    init(
        name: String,
        quantity: String = "",
        isChecked: Bool = false,
        category: String = "Other"
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.isChecked = isChecked
        self.category = category
    }
}
