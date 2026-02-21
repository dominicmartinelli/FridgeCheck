# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `FridgeCheck.xcodeproj` in Xcode 15+. No package dependencies — everything is native Apple frameworks.

```bash
# Build from CLI (requires Xcode Command Line Tools)
xcodebuild -project FridgeCheck.xcodeproj -scheme FridgeCheck -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (none currently defined)
xcodebuild -project FridgeCheck.xcodeproj -scheme FridgeCheck test
```

The app requires a Claude API key entered at runtime via the Settings tab. There is no `.env` or config file — the key is stored in `UserPreferences` (SwiftData).

## Architecture

**SwiftUI + MVVM + SwiftData**, targeting iOS 17+.

### Data Flow

```
ClaudeAPIService (actor) ──► ScanViewModel ──► SwiftUI Views
                                  │
                           SwiftData ModelContext
                                  │
              Recipe / PantryItem / MealPlan / ShoppingListItem / ScanRecord / UserPreferences
```

All ViewModels use the `@Observable` macro (not `ObservableObject`). ModelContext is passed into ViewModel methods as a parameter rather than injected at init — this is the consistent pattern across all ViewModels.

### Key Files

- `Services/ClaudeAPIService.swift` — `actor` that wraps all Anthropic API calls. Two entry points: `analyzeImages()` for ingredient detection and `generateRecipes()` for recipe suggestions. Uses `claude-sonnet-4-5-20250929`. Handles JSON extraction from markdown code fences in responses.
- `Services/ImageService.swift` — `UIViewControllerRepresentable` wrappers for `CameraPicker` and `PhotoPicker` (up to 5 images).
- `ViewModels/ScanViewModel.swift` — The most complex ViewModel; orchestrates the full scan flow: capture → analyze → select ingredients → generate recipes → save to pantry/history.
- `Models/UserPreferences.swift` — Singleton-style SwiftData model storing the API key and dietary preferences (restrictions, allergies, cuisine preferences).

### Claude API Integration

- Model: `claude-sonnet-4-5-20250929`
- Images are resized to max 1536px and JPEG-compressed at 0.6 before sending
- Responses expected as JSON; service strips markdown code fences before decoding
- Error enum: `ClaudeAPIError` with cases for `noAPIKey`, `invalidResponse`, `decodingError`, `apiError`, `networkError`, `noImages`

### Patterns to Follow

- **@Observable ViewModels**: Use `@Observable` class, not `ObservableObject`/`@Published`
- **ModelContext passing**: Pass `ModelContext` as a function parameter to ViewModel methods (e.g., `func save(context: ModelContext)`)
- **Actor for services**: `ClaudeAPIService` is an `actor` — await all calls to it
- **Category constants**: Ingredient categories and their UI colors are defined as extensions in `Utilities/Extensions.swift` (`String.ingredientCategories`, `Color.categoryColor()`)
- **External storage for images**: ScanRecord uses `@Attribute(.externalStorage)` for image data arrays

### SwiftData Models

`Ingredient`, `Recipe`, `PantryItem`, `ShoppingListItem`, `MealPlan`, `ScanRecord`, `UserPreferences` — all decorated with `@Model`. The model container is configured in `FridgeCheckApp.swift`.

`PantryItem` has computed properties `isExpired` and `isExpiringSoon` (3-day threshold). `Recipe` has `totalTime` computed from `prepTime + cookTime`.
