import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    @State private var apiKey = ""
    @State private var servingSize = 2
    @State private var selectedDietary: Set<String> = []
    @State private var selectedAllergies: Set<String> = []
    @State private var selectedCuisines: Set<String> = []
    @State private var hasLoaded = false
    @State private var showSavedConfirmation = false
    @State private var isTesting = false
    @State private var testResult: Bool?

    private var userPreferences: UserPreferences {
        if let existing = preferences.first {
            return existing
        }
        let new = UserPreferences()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        NavigationStack {
            Form {
                // API Key
                Section {
                    SecureField("Claude API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onChange(of: apiKey) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            userPreferences.apiKey = trimmed
                            showSavedConfirmation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showSavedConfirmation = false
                                }
                            }
                        }

                    if showSavedConfirmation {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .transition(.opacity)
                    }

                    Button {
                        Task {
                            await testAPIKey()
                        }
                    } label: {
                        HStack {
                            Label("Test API Key", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else if let testResult {
                                Image(systemName: testResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(testResult ? .green : .red)
                            }
                        }
                    }
                    .disabled(apiKey.isEmpty || isTesting)
                } header: {
                    Text("API Configuration")
                } footer: {
                    if let testResult, !testResult {
                        Text("Key test failed. Check that the key is correct and your account has active billing.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Your API key is stored locally on your device and saves automatically. Get one at console.anthropic.com")
                    }
                }

                // Serving Size
                Section("Serving Size") {
                    Stepper("\(servingSize) people", value: $servingSize, in: 1...12)
                        .onChange(of: servingSize) { _, newValue in
                            userPreferences.servingSize = newValue
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
                                userPreferences.dietaryRestrictions = Array(selectedDietary)
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
                                userPreferences.allergies = Array(selectedAllergies)
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
                                userPreferences.cuisinePreferences = Array(selectedCuisines)
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
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Powered by")
                        Spacer()
                        Text("Claude AI")
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
                    loadPreferences()
                    hasLoaded = true
                }
            }
        }
    }

    private func loadPreferences() {
        let prefs = userPreferences
        apiKey = prefs.apiKey
        servingSize = prefs.servingSize
        selectedDietary = Set(prefs.dietaryRestrictions)
        selectedAllergies = Set(prefs.allergies)
        selectedCuisines = Set(prefs.cuisinePreferences)
    }

    private func testAPIKey() async {
        isTesting = true
        testResult = nil

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testResult = false
            isTesting = false
            return
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            testResult = false
            isTesting = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "test"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run {
                testResult = status == 200
                isTesting = false
            }
        } catch {
            await MainActor.run {
                testResult = false
                isTesting = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [
            UserPreferences.self, ShoppingListItem.self,
            Recipe.self
        ], inMemory: true)
}
