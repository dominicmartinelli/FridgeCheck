import SwiftUI

extension Date {
    var formatted_short: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }

    var formatted_medium: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }

    var formatted_relative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }

    var dayAndMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    func startOfWeek(using calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
}

extension Color {
    static let appGreen = Color("AccentColor")
    static let expiryRed = Color.red.opacity(0.8)
    static let expiryYellow = Color.orange.opacity(0.8)
    static let freshGreen = Color.green.opacity(0.8)

    static func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "produce": return .green
        case "dairy": return .blue
        case "meat": return .red
        case "seafood": return .cyan
        case "grains": return .orange
        case "condiments": return .yellow
        case "beverages": return .purple
        case "snacks": return .pink
        case "frozen": return .indigo
        default: return .gray
        }
    }
}

extension String {
    static let ingredientCategories = [
        "Produce", "Dairy", "Meat", "Seafood", "Grains",
        "Condiments", "Beverages", "Snacks", "Frozen", "Other"
    ]

    static let mealTypes = ["Breakfast", "Lunch", "Dinner"]

    static let dietaryOptions = [
        "Vegetarian", "Vegan", "Keto", "Paleo",
        "Gluten-Free", "Low-Carb", "Low-Fat", "Mediterranean"
    ]

    static let allergyOptions = [
        "Nuts", "Peanuts", "Gluten", "Dairy", "Eggs",
        "Soy", "Shellfish", "Fish", "Sesame", "Wheat"
    ]

    static let cuisineOptions = [
        "Italian", "Mexican", "Chinese", "Japanese", "Indian",
        "Thai", "French", "Mediterranean", "American", "Korean"
    ]
}
