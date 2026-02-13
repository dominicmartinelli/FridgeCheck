import Foundation
import SwiftData

@Model
final class PantryItem {
    var id: UUID
    var name: String
    var category: String
    var quantity: String
    var dateAdded: Date
    var expiryDate: Date?

    var isExpired: Bool {
        guard let expiryDate else { return false }
        return expiryDate < Date()
    }

    var isExpiringSoon: Bool {
        guard let expiryDate else { return false }
        let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return expiryDate <= threeDays && !isExpired
    }

    init(
        name: String,
        category: String = "Other",
        quantity: String = "",
        expiryDate: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.quantity = quantity
        self.dateAdded = Date()
        self.expiryDate = expiryDate
    }
}
