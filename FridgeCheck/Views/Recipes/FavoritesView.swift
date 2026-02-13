import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Recipe> { $0.isFavorite },
           sort: \Recipe.dateCreated,
           order: .reverse) private var favorites: [Recipe]

    var body: some View {
        Group {
            if favorites.isEmpty {
                    ContentUnavailableView {
                        Label("No Favorites", systemImage: "heart")
                    } description: {
                        Text("Tap the heart icon on any recipe to save it to your favorites.")
                    }
                } else {
                    List(favorites) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.title)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Text(recipe.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    HStack(spacing: 10) {
                                        if !recipe.cuisineType.isEmpty {
                                            Text(recipe.cuisineType)
                                                .font(.caption2)
                                        }
                                        Label("\(recipe.totalTime)m", systemImage: "timer")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button {
                                recipe.isFavorite = false
                            } label: {
                                Label("Unfavorite", systemImage: "heart.slash")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
    }
}

#Preview {
    FavoritesView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
