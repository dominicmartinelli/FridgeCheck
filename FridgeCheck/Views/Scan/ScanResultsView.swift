import SwiftUI
import SwiftData

struct ScanResultsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @Query private var pantryItems: [PantryItem]
    @Bindable var viewModel: ScanViewModel
    @State private var navigateToRecipes = false
    @State private var showAddedToPantryConfirmation = false

    private var userPreferences: UserPreferences? {
        preferences.first
    }

    private var selectedCount: Int {
        viewModel.detectedIngredients.filter(\.isSelected).count
    }

    var body: some View {
        ZStack {
            if viewModel.isAnalyzing {
                analyzingStateView
            } else if viewModel.detectedIngredients.isEmpty && !viewModel.isAnalyzing {
                emptyStateView
            } else {
                resultsContentView
            }
        }
        .navigationTitle("Scan Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.detectedIngredients.isEmpty {
                    Menu {
                        Button("Select All") {
                            selectAll()
                        }
                        Button("Deselect All") {
                            deselectAll()
                        }
                    } label: {
                        Image(systemName: "checklist")
                    }
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
            if let _ = viewModel.errorMessage, userPreferences?.apiKey.isEmpty ?? true {
                Button("Open Settings") {
                    // In a full app this would navigate to settings
                }
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .overlay(alignment: .bottom) {
            if showAddedToPantryConfirmation {
                addedToPantryBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(isPresented: $navigateToRecipes) {
            RecipeSuggestionsView(viewModel: viewModel)
        }
        .task {
            if viewModel.capturedImage != nil && viewModel.detectedIngredients.isEmpty && !viewModel.isAnalyzing {
                await viewModel.analyzeImage(apiKey: userPreferences?.apiKey ?? "")
            }
        }
    }

    // MARK: - Analyzing State

    private var analyzingStateView: some View {
        VStack(spacing: 24) {
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.primary)
                    }
            }

            VStack(spacing: 8) {
                Text("Analyzing Image...")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Identifying ingredients with AI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Ingredients Detected", systemImage: "carrot")
        } description: {
            Text("No ingredients could be identified in this image. Try taking a clearer photo with good lighting.")
        } actions: {
            Button("Try Again") {
                Task {
                    await viewModel.analyzeImage(apiKey: userPreferences?.apiKey ?? "")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Results Content

    private var resultsContentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Captured image thumbnail
                    capturedImageHeader

                    // Ingredients list header
                    ingredientsHeader

                    // Ingredient rows
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.detectedIngredients) { ingredient in
                            IngredientRow(ingredient: ingredient) {
                                viewModel.toggleIngredient(ingredient)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 160)
            }

            // Bottom action bar
            bottomActionBar
        }
    }

    // MARK: - Captured Image Header

    private var capturedImageHeader: some View {
        Group {
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        .overlay(alignment: .bottomLeading) {
                            Text("\(viewModel.detectedIngredients.count) ingredients found")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                        }
                    }
            }
        }
    }

    // MARK: - Ingredients Header

    private var ingredientsHeader: some View {
        HStack {
            Text("Detected Ingredients")
                .font(.headline)

            Spacer()

            Text("\(selectedCount) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Divider()

            VStack(spacing: 10) {
                Button {
                    navigateToRecipes = true
                    Task {
                        await viewModel.generateRecipes(
                            preferences: userPreferences,
                            pantryItems: pantryItems,
                            apiKey: userPreferences?.apiKey ?? ""
                        )
                    }
                } label: {
                    Label("Get Recipe Suggestions", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedCount > 0 ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedCount == 0)

                Button {
                    viewModel.addIngredientsToPantry(modelContext: modelContext)
                    showAddedToPantryConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            showAddedToPantryConfirmation = false
                        }
                    }
                } label: {
                    Label("Add Selected to Pantry", systemImage: "refrigerator")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedCount == 0)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Confirmation Banner

    private var addedToPantryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("\(selectedCount) ingredients added to pantry")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.bottom, 100)
        .animation(.spring(duration: 0.4), value: showAddedToPantryConfirmation)
    }

    // MARK: - Helpers

    private func selectAll() {
        for ingredient in viewModel.detectedIngredients {
            if !ingredient.isSelected {
                viewModel.toggleIngredient(ingredient)
            }
        }
    }

    private func deselectAll() {
        for ingredient in viewModel.detectedIngredients {
            if ingredient.isSelected {
                viewModel.toggleIngredient(ingredient)
            }
        }
    }
}

// MARK: - Ingredient Row

private struct IngredientRow: View {
    let ingredient: DetectedIngredient
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Checkbox
                Image(systemName: ingredient.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(ingredient.isSelected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))

                // Category color indicator
                Circle()
                    .fill(Color.categoryColor(for: ingredient.category))
                    .frame(width: 10, height: 10)

                // Ingredient info
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(ingredient.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !ingredient.estimatedQuantity.isEmpty {
                            Text("~\(ingredient.estimatedQuantity)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ingredient.isSelected ? Color.accentColor.opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        ingredient.isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: ingredient.isSelected)
    }
}

#Preview("With Ingredients") {
    NavigationStack {
        ScanResultsView(viewModel: {
            let vm = ScanViewModel()
            vm.capturedImage = UIImage(systemName: "photo")
            return vm
        }())
    }
    .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}

#Preview("Loading") {
    NavigationStack {
        ScanResultsView(viewModel: {
            let vm = ScanViewModel()
            vm.isAnalyzing = true
            vm.capturedImage = UIImage(systemName: "photo")
            return vm
        }())
    }
    .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}
