import SwiftUI
import SwiftData

/// Shown after a scan's ingredients are added to the pantry: lists pantry
/// items that didn't appear anywhere in the scan and offers to remove the
/// ones the user has used up. Everything starts selected — one tap keeps the
/// pantry truthful — but nothing is deleted without the explicit Remove tap.
struct ScanDiffReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let items: [PantryItem]
    @State private var selectedIDs: Set<UUID>

    init(items: [PantryItem]) {
        self.items = items
        _selectedIDs = State(initialValue: Set(items.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            toggle(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(item.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(item.id)
                                                     ? Color.accentColor : .secondary)
                                    .contentTransition(.symbolEffect(.replace))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if !item.quantity.isEmpty {
                                        Text(item.quantity)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("These pantry items didn't show up in your scan. Uncheck anything you still have — items out of frame or in a cupboard are easy to miss.")
                }
            }
            .navigationTitle("Used These Up?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep All") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Button(role: .destructive) {
                        removeSelected()
                    } label: {
                        Text("Remove Selected (\(selectedIDs.count))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .disabled(selectedIDs.isEmpty)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial)
            }
        }
    }

    private func toggle(_ item: PantryItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func removeSelected() {
        for item in items where selectedIDs.contains(item.id) {
            modelContext.delete(item)
        }
        dismiss()
    }
}

#Preview {
    ScanDiffReviewView(items: [
        PantryItem(name: "Milk", category: "Dairy", quantity: "1L"),
        PantryItem(name: "Spinach", category: "Produce", quantity: "1 bag")
    ])
    .modelContainer(for: PantryItem.self, inMemory: true)
}
