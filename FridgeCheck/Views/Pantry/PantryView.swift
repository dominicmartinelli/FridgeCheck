import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @State private var viewModel = PantryViewModel()
    @State private var showAddItem = false
    @State private var editingItem: PantryItem?
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Group {
                if pantryItems.isEmpty {
                    ContentUnavailableView {
                        Label("Pantry Empty", systemImage: "refrigerator")
                    } description: {
                        Text("Scan your fridge or add items manually to start tracking your pantry.")
                    } actions: {
                        Button("Add Item") {
                            showAddItem = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $selection) {
                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.categories, id: \.self) { category in
                                    Button(category) {
                                        withAnimation {
                                            viewModel.selectedCategory = category
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        viewModel.selectedCategory == category
                                        ? Color.accentColor
                                        : Color(.systemGray5)
                                    )
                                    .foregroundStyle(
                                        viewModel.selectedCategory == category
                                        ? .white
                                        : .primary
                                    )
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .selectionDisabled()

                        // Grouped items
                        ForEach(viewModel.groupedItems(pantryItems), id: \.0) { category, items in
                            Section {
                                ForEach(items) { item in
                                    itemRow(item)
                                        .tag(item.id)
                                }
                            } header: {
                                HStack {
                                    Circle()
                                        .fill(Color.categoryColor(for: category))
                                        .frame(width: 8, height: 8)
                                    Text(category)
                                }
                            }
                        }
                    }
                    .searchable(text: $viewModel.searchText, prompt: "Search pantry")
                    .safeAreaInset(edge: .bottom) {
                        if editMode.isEditing {
                            bulkActionBar
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Pantry")
            .toolbar {
                if !pantryItems.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        // Not EditButton: toolbar items don't see the injected
                        // editMode environment, so it would toggle its own
                        // state and leave the list out of edit mode.
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !pantryItems.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                viewModel.clearExpired(pantryItems, modelContext: modelContext)
                            } label: {
                                Label("Clear Expired Items", systemImage: "trash.slash")
                            }
                            .disabled(!pantryItems.contains(where: \.isExpired))
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel("More")
                        }
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddPantryItemView()
            }
            .sheet(item: $editingItem) { item in
                AddPantryItemView(item: item)
            }
            .onChange(of: editMode) {
                if !editMode.isEditing {
                    selection.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PantryItem) -> some View {
        let row = PantryItemRow(item: item)
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.deleteItem(item, modelContext: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    viewModel.addToShoppingList(item, modelContext: modelContext)
                } label: {
                    Label("Shopping List", systemImage: "cart.badge.plus")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button {
                    editingItem = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    viewModel.addToShoppingList(item, modelContext: modelContext)
                } label: {
                    Label("Add to Shopping List", systemImage: "cart.badge.plus")
                }
                Button(role: .destructive) {
                    viewModel.deleteItem(item, modelContext: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        // A plain onTapGesture would swallow the taps edit mode needs for
        // selection, so only attach it outside edit mode.
        if editMode.isEditing {
            row
        } else {
            row.onTapGesture {
                editingItem = item
            }
        }
    }

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(role: .destructive) {
                withAnimation {
                    viewModel.deleteItems(ids: selection, from: pantryItems, modelContext: modelContext)
                    selection.removeAll()
                }
            } label: {
                Text("Delete Selected (\(selection.count))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .disabled(selection.isEmpty)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

private struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Added \(item.dateAdded.formatted_relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let expiryDate = item.expiryDate {
                VStack(alignment: .trailing, spacing: 2) {
                    if item.isExpired {
                        Label("Expired", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if item.isExpiringSoon {
                        Label("Expiring", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(expiryDate.formatted_short)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    PantryView()
        .modelContainer(for: [PantryItem.self, ShoppingListItem.self], inMemory: true)
}
