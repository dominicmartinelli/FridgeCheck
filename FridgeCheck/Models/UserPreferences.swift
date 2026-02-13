import Foundation
import SwiftData

@Model
final class UserPreferences {
    var id: UUID
    var dietaryRestrictions: [String]
    var allergies: [String]
    var cuisinePreferences: [String]
    var servingSize: Int
    var apiKey: String

    init(
        dietaryRestrictions: [String] = [],
        allergies: [String] = [],
        cuisinePreferences: [String] = [],
        servingSize: Int = 2,
        apiKey: String = ""
    ) {
        self.id = UUID()
        self.dietaryRestrictions = dietaryRestrictions
        self.allergies = allergies
        self.cuisinePreferences = cuisinePreferences
        self.servingSize = servingSize
        self.apiKey = apiKey
    }
}
