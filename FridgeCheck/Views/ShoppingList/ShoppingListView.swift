import SwiftUI
import SwiftData

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.name) private var items: [ShoppingListItem]
    @State private var viewModel = ShoppingListViewModel()
    @State private var showAddItem = false

    private var checkedCount: Int {
        items.filter(\.isChecked).count
    }

    var body: some View {
        Group {
            if items.isEmpty {
                    ContentUnavailableView {
                        Label("Shopping List Empty", systemImage: "cart")
                    } description: {
                        Text("Add items manually or they'll be added automatically from recipes with missing ingredients.")
                    } actions: {
                        Button("Add Item") {
                            showAddItem = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 0) {
                        List {
                            ForEach(viewModel.groupedItems(items), id: \.0) { category, categoryItems in
                                Section(category) {
                                    ForEach(categoryItems) { item in
                                        ShoppingItemRow(item: item) {
                                            viewModel.toggleItem(item)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                viewModel.deleteItem(item, modelContext: modelContext)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Bottom actions
                        if checkedCount > 0 {
                            bottomActions
                        }
                    }
                }
            }
            .navigationTitle("Shopping List")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                addItemSheet
            }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Divider()

            VStack(spacing: 8) {
                Button {
                    viewModel.addCheckedItemsToPantry(from: items, modelContext: modelContext)
                } label: {
                    Label("Add \(checkedCount) Checked to Pantry", systemImage: "refrigerator")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    viewModel.clearCheckedItems(from: items, modelContext: modelContext)
                } label: {
                    Text("Clear Checked Items")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Add Item Sheet

    private var addItemSheet: some View {
        NavigationStack {
            Form {
                TextField("Item Name", text: $viewModel.newItemName)
                TextField("Quantity", text: $viewModel.newItemQuantity)
                Picker("Category", selection: $viewModel.newItemCategory) {
                    ForEach(String.ingredientCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddItem = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addItem(modelContext: modelContext)
                        showAddItem = false
                    }
                    .disabled(viewModel.newItemName.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)

                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: item.isChecked)
    }
}

#Preview {
    ShoppingListView()
        .modelContainer(for: [ShoppingListItem.self, PantryItem.self], inMemory: true)
}
