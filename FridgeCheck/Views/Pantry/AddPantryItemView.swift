import SwiftUI
import SwiftData

/// Add a new pantry item, or edit an existing one when `item` is provided.
struct AddPantryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let item: PantryItem?

    @State private var name: String
    @State private var category: String
    @State private var quantity: String
    @State private var hasExpiryDate: Bool
    @State private var expiryDate: Date

    init(item: PantryItem? = nil) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? "Other")
        _quantity = State(initialValue: item?.quantity ?? "")
        _hasExpiryDate = State(initialValue: item?.expiryDate != nil)
        _expiryDate = State(initialValue: item?.expiryDate
            ?? Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $category) {
                        ForEach(String.ingredientCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }

                    TextField("Quantity (e.g., 2 bags, 500ml)", text: $quantity)
                }

                Section("Expiry Date") {
                    Toggle("Track Expiry", isOn: $hasExpiryDate)

                    if hasExpiryDate {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(item == nil ? "Add Pantry Item" : "Edit Pantry Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save") {
                        save()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        if let item {
            item.name = name
            item.category = category
            item.quantity = quantity
            item.expiryDate = hasExpiryDate ? expiryDate : nil
        } else {
            PantryItem.upsert(
                name: name,
                category: category,
                quantity: quantity,
                expiryDate: hasExpiryDate ? expiryDate : nil,
                in: modelContext
            )
        }
        dismiss()
    }
}

#Preview {
    AddPantryItemView()
        .modelContainer(for: PantryItem.self, inMemory: true)
}
