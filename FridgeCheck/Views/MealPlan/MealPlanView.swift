import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var mealPlans: [MealPlan]
    @Query(filter: #Predicate<Recipe> { $0.isFavorite }) private var favoriteRecipes: [Recipe]
    @Query private var pantryItems: [PantryItem]
    @State private var viewModel = MealPlanViewModel()
    @State private var showRecipePicker = false
    @State private var selectedMealSlot: (Date, String)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Week navigation
                weekNavigationHeader

                // Day columns
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.weekDates, id: \.self) { date in
                            daySection(for: date)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Meal Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.autoGenerateMealPlan(
                                favorites: favoriteRecipes,
                                pantryItems: pantryItems,
                                modelContext: modelContext
                            )
                        } label: {
                            Label("Auto-Generate Week", systemImage: "sparkles")
                        }

                        Button(role: .destructive) {
                            clearWeekPlan()
                        } label: {
                            Label("Clear Week", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showRecipePicker) {
                recipePickerSheet
            }
        }
    }

    // MARK: - Week Navigation

    private var weekNavigationHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }

            Spacer()

            if let first = viewModel.weekDates.first,
               let last = viewModel.weekDates.last {
                Text("\(first.dayAndMonth) - \(last.dayAndMonth)")
                    .font(.headline)
            }

            Spacer()

            Button {
                viewModel.goToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    // MARK: - Day Section

    private func daySection(for date: Date) -> some View {
        let meals = viewModel.mealsForDate(date, allMealPlans: mealPlans)
        let isToday = Calendar.current.isDateInToday(date)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(date.dayOfWeek)
                    .font(.headline)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)

                Text(date.dayAndMonth)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isToday {
                    Text("Today")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            ForEach(String.mealTypes, id: \.self) { mealType in
                let meal = meals.first { $0.mealType == mealType }
                mealSlotRow(date: date, mealType: mealType, meal: meal)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday ? Color.accentColor.opacity(0.05) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isToday ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Meal Slot Row

    private func mealSlotRow(date: Date, mealType: String, meal: MealPlan?) -> some View {
        HStack(spacing: 10) {
            Text(mealType)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(.secondary)

            if let meal, let recipe = meal.recipe {
                Text(recipe.title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel.deleteMeal(meal, modelContext: modelContext)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Button {
                    selectedMealSlot = (date, mealType)
                    showRecipePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                        Text("Add recipe")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Recipe Picker Sheet

    private var recipePickerSheet: some View {
        NavigationStack {
            List(favoriteRecipes) { recipe in
                Button {
                    if let slot = selectedMealSlot {
                        viewModel.addMeal(
                            date: slot.0,
                            mealType: slot.1,
                            recipe: recipe,
                            modelContext: modelContext
                        )
                    }
                    showRecipePicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            if !recipe.cuisineType.isEmpty {
                                Text(recipe.cuisineType)
                                    .font(.caption)
                            }
                            Label("\(recipe.totalTime)m", systemImage: "timer")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRecipePicker = false
                    }
                }
            }
            .overlay {
                if favoriteRecipes.isEmpty {
                    ContentUnavailableView {
                        Label("No Favorites", systemImage: "heart")
                    } description: {
                        Text("Save recipes as favorites to use them in meal planning.")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func clearWeekPlan() {
        for date in viewModel.weekDates {
            let meals = viewModel.mealsForDate(date, allMealPlans: mealPlans)
            for meal in meals {
                modelContext.delete(meal)
            }
        }
    }
}

#Preview {
    MealPlanView()
        .modelContainer(for: [MealPlan.self, Recipe.self, PantryItem.self], inMemory: true)
}
