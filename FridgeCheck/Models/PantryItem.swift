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

extension PantryItem {
    /// Inserts a pantry item, or refreshes the existing one when a
    /// case-insensitive name match is already in the store — rescanning the
    /// same fridge must not fill the pantry with duplicates.
    @discardableResult
    static func upsert(
        name: String,
        category: String = "Other",
        quantity: String = "",
        expiryDate: Date? = nil,
        in context: ModelContext
    ) -> PantryItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? context.fetch(FetchDescriptor<PantryItem>()))?.first {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if let existing {
            existing.category = category
            if !quantity.isEmpty {
                existing.quantity = quantity
            }
            if let expiryDate {
                existing.expiryDate = expiryDate
            }
            existing.dateAdded = Date()
            return existing
        }
        let item = PantryItem(
            name: trimmed,
            category: category,
            quantity: quantity,
            expiryDate: expiryDate
        )
        context.insert(item)
        return item
    }
}
