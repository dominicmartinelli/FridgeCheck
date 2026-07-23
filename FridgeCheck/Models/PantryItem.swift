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
    /// Pantry items not matched by any scanned ingredient name — candidates
    /// for "you've used this up" cleanup after a scan. Matches loosely on
    /// whole words in either direction (pantry "Whole Milk" counts as seen
    /// when the scan says "Milk") so camera noise doesn't flag items the
    /// user still has.
    static func itemsMissing(fromScan scannedNames: [String], in items: [PantryItem]) -> [PantryItem] {
        let scanWordSets = scannedNames.map(\.ingredientWords).filter { !$0.isEmpty }
        guard !scanWordSets.isEmpty else { return [] }
        return items.filter { item in
            let itemWords = item.name.ingredientWords
            guard !itemWords.isEmpty else { return false }
            return !scanWordSets.contains { scanWords in
                scanWords.isSubset(of: itemWords) || itemWords.isSubset(of: scanWords)
            }
        }
    }

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
