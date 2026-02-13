import SwiftUI
import SwiftData

@Observable
final class MealPlanViewModel {
    var selectedDate = Date()
    var weekDates: [Date] = []

    init() {
        updateWeekDates()
    }

    func updateWeekDates() {
        let calendar = Calendar.current
        let startOfWeek = selectedDate.startOfWeek(using: calendar)
        weekDates = (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)
        }
    }

    func goToNextWeek() {
        if let next = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
            selectedDate = next
            updateWeekDates()
        }
    }

    func goToPreviousWeek() {
        if let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
            selectedDate = prev
            updateWeekDates()
        }
    }

    func mealsForDate(_ date: Date, allMealPlans: [MealPlan]) -> [MealPlan] {
        let calendar = Calendar.current
        return allMealPlans.filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.mealType < $1.mealType }
    }

    func addMeal(date: Date, mealType: String, recipe: Recipe?, modelContext: ModelContext) {
        let plan = MealPlan(date: date, mealType: mealType, recipe: recipe)
        modelContext.insert(plan)
    }

    func deleteMeal(_ meal: MealPlan, modelContext: ModelContext) {
        modelContext.delete(meal)
    }

    func autoGenerateMealPlan(
        favorites: [Recipe],
        pantryItems: [PantryItem],
        modelContext: ModelContext
    ) {
        guard !favorites.isEmpty else { return }
        let calendar = Calendar.current

        for date in weekDates {
            for mealType in String.mealTypes {
                let existing = mealsForDate(date, allMealPlans: [])
                let alreadyPlanned = existing.contains { $0.mealType == mealType }
                if !alreadyPlanned {
                    let randomRecipe = favorites.randomElement()
                    let plan = MealPlan(
                        date: calendar.startOfDay(for: date),
                        mealType: mealType,
                        recipe: randomRecipe
                    )
                    modelContext.insert(plan)
                }
            }
        }
    }
}
