# Fridge Check

An iOS app that uses Claude's vision API to scan your fridge, identify ingredients, and suggest recipes. Authentication and all Claude calls are proxied through a small Go backend (`server/`) that enforces per-user daily quotas, so no API key ever leaves the backend.

## Features

- **Fridge Scanning** — Take a photo of your fridge and let AI identify all visible ingredients
- **Recipe Suggestions** — Get personalized recipes based on what you have, with full instructions and nutritional info
- **Pantry Tracking** — Keep inventory of your ingredients with expiry date warnings
- **Shopping Lists** — Auto-generate lists from missing recipe ingredients, check items off as you shop
- **Meal Planning** — Weekly calendar view to plan breakfast, lunch, and dinner
- **Favorites** — Save and organize your best recipes
- **Dietary Preferences** — Set restrictions (vegetarian, keto, etc.), allergies, and cuisine preferences

## Tech Stack

- **SwiftUI** with MVVM architecture
- **SwiftData** for persistence
- **Sign in with Apple** for auth (identity token exchanged for a session JWT stored in Keychain)
- **Go backend** in the `server/` subdirectory that proxies Claude (`claude-sonnet-4-5-20250929`) and enforces quotas
- iOS 17+ deployment target

## Setup

The iOS client talks to the backend at `https://fridge.dkm.net` (see `FridgeCheck/Services/AppConfig.swift`). For the production app you don't need to run anything yourself — just sign in with Apple. For local development against your own backend, see `server/README.md`.

1. Clone the repo and open `FridgeCheck.xcodeproj` in Xcode
2. Set your development team in Signing & Capabilities (Sign in with Apple is required)
3. Build and run on a simulator or device
4. On first launch, tap **Sign in with Apple** — the app exchanges the Apple identity token for a session JWT at `POST /v1/auth/apple`, then stores the JWT in the iOS Keychain (`FridgeCheck/Services/KeychainStore.swift`)
5. Go to the **Scan** tab and take a photo of your fridge

The free tier allows 5 scans and 20 recipe generations per user per day. Beyond that the app surfaces a quota-exceeded message until the next UTC day. To run the backend yourself or move to the unlimited tier, see `server/README.md`.

## Project Structure

```
FridgeCheck/
├── Models/          # SwiftData models (Recipe, PantryItem, MealPlan, etc.)
├── Services/        # Backend API client, auth, keychain, camera/photo helpers
├── ViewModels/      # Observable view models for each feature
├── Views/           # SwiftUI views organized by feature
│   ├── Home/        # Dashboard with recent scans and today's meals
│   ├── Scan/        # Camera capture → ingredient detection → recipe suggestions
│   ├── Pantry/      # Ingredient inventory with expiry tracking
│   ├── Recipes/     # Browse, search, and filter saved recipes
│   ├── ShoppingList/# Checkable shopping list with pantry integration
│   ├── MealPlan/    # Weekly meal calendar
│   └── Settings/    # Dietary preferences, allergies, account
└── Utilities/       # Date formatting and color helpers

server/              # Go backend (chi, SQLite, JWT) — see server/README.md
```

## Requirements

- Xcode 15+
- iOS 17+
- An Apple ID for Sign in with Apple (the backend handles all Claude billing)
