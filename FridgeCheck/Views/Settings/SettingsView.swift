import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var auth = AuthService.shared

    @State private var servingSize = 2
    @State private var selectedDietary: Set<String> = []
    @State private var selectedAllergies: Set<String> = []
    @State private var selectedCuisines: Set<String> = []
    @State private var hasLoaded = false
    @State private var prefs: UserPreferences?
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    private let api = FridgeCheckAPIService()

    private func ensurePreferences() -> UserPreferences {
        if let existing = preferences.first { return existing }
        let new = UserPreferences()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        NavigationStack {
            Form {
                // Account
                Section {
                    HStack {
                        Label("Signed In", systemImage: "person.crop.circle.fill")
                        Spacer()
                        Text(auth.userEmail ?? "Apple ID")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Deleting your account permanently removes your scan history and usage data from our servers.")
                }

                // Serving Size
                Section("Serving Size") {
                    Stepper("\(servingSize) people", value: $servingSize, in: 1...12)
                        .onChange(of: servingSize) { _, newValue in
                            prefs?.servingSize = newValue
                        }
                }

                // Dietary Restrictions
                Section {
                    ForEach(String.dietaryOptions, id: \.self) { option in
                        Toggle(option, isOn: Binding(
                            get: { selectedDietary.contains(option) },
                            set: { isOn in
                                if isOn {
                                    selectedDietary.insert(option)
                                } else {
                                    selectedDietary.remove(option)
                                }
                                prefs?.dietaryRestrictions = Array(selectedDietary)
                            }
                        ))
                    }
                } header: {
                    Text("Dietary Restrictions")
                }

                // Allergies
                Section {
                    ForEach(String.allergyOptions, id: \.self) { option in
                        Toggle(option, isOn: Binding(
                            get: { selectedAllergies.contains(option) },
                            set: { isOn in
                                if isOn {
                                    selectedAllergies.insert(option)
                                } else {
                                    selectedAllergies.remove(option)
                                }
                                prefs?.allergies = Array(selectedAllergies)
                            }
                        ))
                    }
                } header: {
                    Text("Allergies")
                } footer: {
                    Text("Select any food allergies. These will be strictly avoided in recipe suggestions.")
                }

                // Cuisine Preferences
                Section {
                    ForEach(String.cuisineOptions, id: \.self) { option in
                        Toggle(option, isOn: Binding(
                            get: { selectedCuisines.contains(option) },
                            set: { isOn in
                                if isOn {
                                    selectedCuisines.insert(option)
                                } else {
                                    selectedCuisines.remove(option)
                                }
                                prefs?.cuisinePreferences = Array(selectedCuisines)
                            }
                        ))
                    }
                } header: {
                    Text("Cuisine Preferences")
                }

                // Navigation links
                Section("More") {
                    NavigationLink {
                        ShoppingListView()
                    } label: {
                        Label("Shopping List", systemImage: "cart")
                    }

                    NavigationLink {
                        FavoritesView()
                    } label: {
                        Label("Favorites", systemImage: "heart")
                    }

                    NavigationLink {
                        RecipeListView()
                    } label: {
                        Label("All Recipes", systemImage: "book")
                    }

                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2.2")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .onAppear {
                if !hasLoaded {
                    prefs = ensurePreferences()
                    loadPreferences()
                    hasLoaded = true
                }
            }
            .confirmationDialog(
                "Sign Out?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to use the app.")
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all server-side data. This cannot be undone.")
            }
            .alert("Couldn't Delete Account", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func deleteAccount() async {
        guard let token = auth.sessionToken, !token.isEmpty else {
            auth.signOut()
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteAccount(sessionToken: token)
            auth.signOut()
        } catch {
            // An expired session can't authorize the delete — sign out so the
            // user can sign in again and retry.
            if case FridgeCheckAPIService.APIError.sessionExpired = error {
                auth.signOut()
                return
            }
            deleteError = error.localizedDescription
        }
    }

    private func loadPreferences() {
        guard let prefs else { return }
        servingSize = prefs.servingSize
        selectedDietary = Set(prefs.dietaryRestrictions)
        selectedAllergies = Set(prefs.allergies)
        selectedCuisines = Set(prefs.cuisinePreferences)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [
            UserPreferences.self, ShoppingListItem.self,
            Recipe.self
        ], inMemory: true)
}
