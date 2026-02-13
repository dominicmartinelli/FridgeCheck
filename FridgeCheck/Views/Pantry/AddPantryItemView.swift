import SwiftUI
import SwiftData

struct AddPantryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "Other"
    @State private var quantity = ""
    @State private var hasExpiryDate = false
    @State private var expiryDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()

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
            .navigationTitle("Add Pantry Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addItem() {
        let item = PantryItem(
            name: name,
            category: category,
            quantity: quantity,
            expiryDate: hasExpiryDate ? expiryDate : nil
        )
        modelContext.insert(item)
        dismiss()
    }
}

#Preview {
    AddPantryItemView()
        .modelContainer(for: PantryItem.self, inMemory: true)
}
