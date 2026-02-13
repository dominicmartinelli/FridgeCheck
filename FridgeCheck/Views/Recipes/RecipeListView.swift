import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.dateCreated, order: .reverse) private var recipes: [Recipe]
    @State private var viewModel = RecipeViewModel()

    var body: some View {
        Group {
            if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No Recipes", systemImage: "fork.knife")
                    } description: {
                        Text("Scan your fridge to get recipe suggestions, then save your favorites here.")
                    }
                } else {
                    List {
                        // Filters
                        filtersSection

                        // Recipe list
                        ForEach(viewModel.filteredRecipes(recipes)) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                RecipeListRow(recipe: recipe)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.deleteRecipe(recipe, modelContext: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.toggleFavorite(recipe)
                                } label: {
                                    Label(
                                        recipe.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                                    )
                                }
                                .tint(recipe.isFavorite ? .gray : .red)
                            }
                        }
                    }
                    .searchable(text: $viewModel.searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Recipes")
    }

    private var filtersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.cuisines, id: \.self) { cuisine in
                        FilterChip(
                            title: cuisine,
                            isSelected: viewModel.selectedCuisine == cuisine
                        ) {
                            withAnimation {
                                viewModel.selectedCuisine = cuisine
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.difficulties, id: \.self) { difficulty in
                        FilterChip(
                            title: difficulty,
                            isSelected: viewModel.selectedDifficulty == difficulty
                        ) {
                            withAnimation {
                                viewModel.selectedDifficulty = difficulty
                            }
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}

private struct RecipeListRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.body)
                        .fontWeight(.medium)

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(recipe.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if !recipe.cuisineType.isEmpty {
                        Text(recipe.cuisineType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(recipe.totalTime)m", systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(recipe.difficulty)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecipeListView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
