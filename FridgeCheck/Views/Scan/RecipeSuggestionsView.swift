import SwiftUI
import SwiftData

struct RecipeSuggestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: ScanViewModel
    @State private var savedRecipeIDs: Set<UUID> = []

    var body: some View {
        ZStack {
            if viewModel.isGeneratingRecipes {
                generatingStateView
            } else if viewModel.suggestedRecipes.isEmpty && !viewModel.isGeneratingRecipes {
                emptyStateView
            } else {
                recipesListView
            }
        }
        .navigationTitle("Recipe Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.suggestedRecipes.isEmpty {
                    Text("\(viewModel.suggestedRecipes.count) recipes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Generating State

    private var generatingStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            VStack(spacing: 8) {
                Text("Generating Recipes...")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Creating personalized recipes\nbased on your ingredients")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .controlSize(.large)

            // Show which ingredients are being used
            if !viewModel.detectedIngredients.isEmpty {
                let selected = viewModel.detectedIngredients.filter(\.isSelected)
                if !selected.isEmpty {
                    VStack(spacing: 8) {
                        Text("Using \(selected.count) ingredients")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 6) {
                            ForEach(selected) { ingredient in
                                Text(ingredient.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Recipes Yet", systemImage: "fork.knife")
        } description: {
            Text("Could not generate recipe suggestions. Please check your API key and try again.")
        } actions: {
            Button("Retry") {
                // This will be re-triggered via the parent view
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Recipes List

    private var recipesListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.suggestedRecipes, id: \.id) { recipe in
                    NavigationLink {
                        RecipeDetailView(
                            recipe: recipe,
                            isSaved: savedRecipeIDs.contains(recipe.id),
                            onSave: { saveRecipe(recipe) }
                        )
                    } label: {
                        RecipeCard(
                            recipe: recipe,
                            isSaved: savedRecipeIDs.contains(recipe.id),
                            onSave: {
                                saveRecipe(recipe)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Save scan record button
                Button {
                    viewModel.saveScanRecord(modelContext: modelContext)
                } label: {
                    Label("Save Scan to History", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemGray6))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Actions

    private func saveRecipe(_ recipe: Recipe) {
        guard !savedRecipeIDs.contains(recipe.id) else { return }
        modelContext.insert(recipe)
        savedRecipeIDs.insert(recipe.id)
    }
}

// MARK: - Recipe Card

private struct RecipeCard: View {
    let recipe: Recipe
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and save button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if !recipe.cuisineType.isEmpty {
                            Label(recipe.cuisineType, systemImage: "fork.knife")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        DifficultyBadge(difficulty: recipe.difficulty)
                    }
                }

                Spacer()

                Button {
                    onSave()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundStyle(isSaved ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(isSaved)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Summary
            Text(recipe.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Time and nutrition info
            HStack(spacing: 0) {
                // Prep time
                timeInfoItem(
                    icon: "clock",
                    label: "Prep",
                    value: "\(recipe.prepTime)m"
                )

                Divider()
                    .frame(height: 32)

                // Cook time
                timeInfoItem(
                    icon: "flame",
                    label: "Cook",
                    value: "\(recipe.cookTime)m"
                )

                Divider()
                    .frame(height: 32)

                // Total time
                timeInfoItem(
                    icon: "timer",
                    label: "Total",
                    value: "\(recipe.totalTime)m"
                )
            }
            .padding(.vertical, 10)

            // Nutritional info
            if !recipe.nutritionalInfo.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    Image(systemName: "leaf")
                        .font(.caption2)
                        .foregroundStyle(.green)

                    Text(recipe.nutritionalInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // Source ingredients
            if !recipe.sourceIngredients.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "basket")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ForEach(recipe.sourceIngredients, id: \.self) { ingredient in
                            Text(ingredient)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func timeInfoItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Difficulty Badge

private struct DifficultyBadge: View {
    let difficulty: String

    private var color: Color {
        switch difficulty.lowercased() {
        case "easy": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .gray
        }
    }

    var body: some View {
        Text(difficulty)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct ArrangementResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}

// MARK: - Recipe Detail View (Placeholder for navigation)

struct RecipeDetailView: View {
    let recipe: Recipe
    var onSave: (() -> Void)? = nil
    @State private var isSaved: Bool

    init(recipe: Recipe, isSaved: Bool = true, onSave: (() -> Void)? = nil) {
        self.recipe = recipe
        self._isSaved = State(initialValue: isSaved)
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(recipe.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        if !recipe.cuisineType.isEmpty {
                            Label(recipe.cuisineType, systemImage: "fork.knife")
                                .font(.subheadline)
                        }
                        DifficultyBadge(difficulty: recipe.difficulty)
                        Label("\(recipe.totalTime) min", systemImage: "timer")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Time cards
                HStack(spacing: 12) {
                    TimeCard(icon: "clock", title: "Prep", minutes: recipe.prepTime)
                    TimeCard(icon: "flame", title: "Cook", minutes: recipe.cookTime)
                    TimeCard(icon: "timer", title: "Total", minutes: recipe.totalTime)
                }
                .padding(.horizontal)

                // Nutritional info
                if !recipe.nutritionalInfo.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nutrition", systemImage: "leaf")
                            .font(.headline)

                        Text(recipe.nutritionalInfo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                }

                // Ingredients section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ingredients (\(recipe.ingredients.count))", systemImage: "basket")
                        .font(.headline)

                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 6)

                            Text(ingredient)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal)

                // Steps section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Instructions (\(recipe.steps.count) steps)", systemImage: "list.number")
                        .font(.headline)

                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor)
                                .clipShape(Circle())

                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    if onSave != nil  {
                        Button {
                            handleSave()
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(isSaved ? Color.accentColor : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .disabled(isSaved)
                    }

                    Button {
                        if !isSaved { handleSave() }
                        recipe.isFavorite.toggle()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? .red : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
        }
    }

    private func handleSave() {
        onSave?()
        isSaved = true
    }
}

// MARK: - Time Card

private struct TimeCard: View {
    let icon: String
    let title: String
    let minutes: Int

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            Text("\(minutes)")
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("With Recipes") {
    NavigationStack {
        RecipeSuggestionsView(viewModel: {
            let vm = ScanViewModel()
            return vm
        }())
    }
    .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}

#Preview("Loading") {
    NavigationStack {
        RecipeSuggestionsView(viewModel: {
            let vm = ScanViewModel()
            vm.isGeneratingRecipes = true
            return vm
        }())
    }
    .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}
