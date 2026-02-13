import Foundation
import SwiftData

@Model
final class Ingredient {
    var id: UUID
    var name: String
    var category: String

    init(name: String, category: String = "Other") {
        self.id = UUID()
        self.name = name
        self.category = category
    }
}
