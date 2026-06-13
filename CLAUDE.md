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

The app has no runtime secrets. All Claude calls go through the Go backend (base URL in `Services/AppConfig.swift`), which holds the Anthropic API key and enforces per-user quotas. The user authenticates with Sign in with Apple; the resulting session JWT lives in the iOS Keychain.

## Architecture

**SwiftUI + MVVM + SwiftData**, targeting iOS 17+.

### Data Flow

```
AuthService (@Observable, @MainActor)   FridgeCheckAPIService (actor)
         │                                       │
         └──► session JWT in Keychain ───────────┘
                                  │
                          ViewModels (@Observable)
                                  │
                           SwiftUI Views
                                  │
                           SwiftData ModelContext
                                  │
    Recipe / PantryItem / MealPlan / ShoppingListItem / ScanRecord / Ingredient / UserPreferences
```

ViewModels use the `@Observable` macro (not `ObservableObject`). ModelContext is passed into ViewModel methods as a parameter rather than injected at init — this is the consistent pattern across all ViewModels.

### Auth Flow

1. User taps Sign in with Apple; we receive an `ASAuthorizationAppleIDCredential` with an `identityToken`.
2. `AuthService.handleAppleCredential(_:)` POSTs that token to `POST {AppConfig.serverURL}/v1/auth/apple` as `{"identityToken": "..."}`.
3. Server returns `{"session": "<jwt>", "userId": "..."}`. The JWT is stored in Keychain under account `session_token` via `KeychainStore`.
4. All subsequent API calls attach `Authorization: Bearer <jwt>`. Callers read `AuthService.shared.sessionToken` and pass it down to the API service methods.
5. `AuthService.signOut()` deletes the Keychain entries and clears in-memory state.

### Key Files

- `Services/AppConfig.swift` — Single constant: `serverURL`, the backend base URL.
- `Services/AuthService.swift` — `@Observable @MainActor` singleton. Owns `sessionToken`, `userEmail`, `isSigningIn`, `errorMessage`. Exchanges Apple identity tokens at `/v1/auth/apple`.
- `Services/KeychainStore.swift` — Thin wrapper over `SecItem*` keyed by service `com.fridgecheck.app`. Accounts used: `session_token`, `session_email`. Access class is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `Services/FridgeCheckAPIService.swift` — `actor` that wraps backend calls. Entry points: `analyzeImages(_:sessionToken:)` → `POST /v1/scan`, and `generateRecipes(...sessionToken:)` → `POST /v1/recipes`. Both require a non-empty session token and throw `APIError.notSignedIn` otherwise.
- `Services/ImageService.swift` — `UIViewControllerRepresentable` wrappers for `CameraPicker` and `PhotoPicker` (up to 15 images). Note: the resize/JPEG logic actually lives in `FridgeCheckAPIService` (`resizeImage(_:maxDimension:)`), not here.
- `ViewModels/ScanViewModel.swift` — The most complex ViewModel; orchestrates the full scan flow: capture → analyze → select ingredients → generate recipes → save to pantry/history. Takes `sessionToken: String` on its async methods.
- `Models/UserPreferences.swift` — SwiftData model storing dietary preferences only: `dietaryRestrictions`, `allergies`, `cuisinePreferences`, `servingSize`. No credentials.

### Backend API Integration

- Base URL: `AppConfig.serverURL`
- Endpoints consumed by the app:
  - `POST /v1/auth/apple` — body `{identityToken}`, returns `{session, userId}` (called by `AuthService`)
  - `POST /v1/scan` — body `{images: [base64JPEG]}`, returns `{ingredients: [...]}`
  - `POST /v1/recipes` — body `{ingredients, dietaryRestrictions, allergies, cuisinePreferences, servingSize, pantryItems}`, returns `{recipes: [...]}`
  - `GET /v1/me` — current user + today's usage (exposed by the backend; wire a client method here when adding a usage-meter UI)
- All authenticated requests: `Authorization: Bearer <session JWT>`, `Content-Type: application/json`, `timeoutInterval: 300`.
- Images are resized to max 1024px (longest side) and JPEG-compressed at quality 0.6 before base64 encoding — see `FridgeCheckAPIService.resizeImage(_:maxDimension:)` and the `jpegData(compressionQuality: 0.6)` call in `analyzeImages`. Image tokens scale with pixel count; don't raise the dimension without re-checking scan cost.
- Error enum: `FridgeCheckAPIService.APIError` with cases `notSignedIn`, `sessionExpired` (HTTP 401 — callers sign the user out), `invalidImage`, `networkError(Error)`, `decodingError(String)`, `quotaExceeded(used:limit:)` (parsed from HTTP 429 body), `serverError(Int, String)`. Auth errors live in the separate `AuthError` enum in `AuthService.swift`.
- Quota model: free tier is 5 scans and 20 recipe generations per rolling 24-hour window per user; the server returns HTTP 429 with `{error, used, limit}` which is surfaced as `APIError.quotaExceeded`. The unlimited tier has no cap.
- The server sends `output_config` (structured outputs) on every Claude request, so configured models must support it: Haiku 4.5 / Sonnet 4.6 or newer — **not** Sonnet 4.5.
- Recipe hybrid: when `recipe_api_key` is set in the server config, `POST /v1/recipes` first tries curated recipes from recipe-api.com (`server/recipeapi/`) and falls back to Claude generation when matches are thin (<2), preferences can't be expressed as catalog filters (e.g. Paleo, shellfish allergy), or credits are in cool-down. The response shape is identical either way — the app can't tell the sources apart.

### Patterns to Follow

- **@Observable ViewModels**: Use `@Observable` class, not `ObservableObject`/`@Published`.
- **ModelContext passing**: Pass `ModelContext` as a function parameter to ViewModel methods (e.g., `func save(context: ModelContext)`), not stored on the ViewModel.
- **Actor for services**: `FridgeCheckAPIService` is an `actor` — await all calls. Construct one instance and share it; do not introduce ad-hoc URLSession calls in ViewModels.
- **Session token plumbing**: ViewModel methods that hit the backend take `sessionToken: String` as a parameter. Views read it from `AuthService.shared.sessionToken` and pass it down — don't have services or ViewModels reach into `AuthService` directly.
- **Category constants**: Ingredient categories and their UI colors are defined as extensions in `Utilities/Extensions.swift` (`String.ingredientCategories`, `Color.categoryColor()`).
- **External storage for images**: `ScanRecord.imageDataItems` uses `@Attribute(.externalStorage)` so SwiftData keeps the JPEG blobs out of the main store file.

### SwiftData Models

`Ingredient`, `Recipe`, `PantryItem`, `ShoppingListItem`, `MealPlan`, `ScanRecord`, `UserPreferences` — all decorated with `@Model` and living in `FridgeCheck/Models/`. The model container is configured in `FridgeCheckApp.swift`.

`PantryItem` has computed properties `isExpired` and `isExpiringSoon` (3-day threshold). `Recipe` has `totalTime` computed from `prepTime + cookTime`. `UserPreferences` stores only dietary settings — no auth state.

## Server Backend

The Go backend that this app talks to lives in `server/` in the same repo. For backend architecture, endpoints, deploy, and local dev against a custom backend URL, see `server/README.md`.
