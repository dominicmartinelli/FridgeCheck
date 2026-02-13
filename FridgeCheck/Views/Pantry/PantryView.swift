import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @State private var viewModel = PantryViewModel()
    @State private var showAddItem = false

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
                    List {
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

                        // Grouped items
                        ForEach(viewModel.groupedItems(pantryItems), id: \.0) { category, items in
                            Section {
                                ForEach(items) { item in
                                    PantryItemRow(item: item)
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
                }
            }
            .navigationTitle("Pantry")
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
                AddPantryItemView()
            }
        }
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
