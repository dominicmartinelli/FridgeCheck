# Fridge Check

An iOS app that uses Claude's vision API to scan your fridge, identify ingredients, and suggest recipes.

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
- **Claude API** (claude-sonnet-4-5-20250929 vision) for image analysis and recipe generation
- iOS 17+ deployment target

## Setup

1. Clone the repo and open `FridgeCheck.xcodeproj` in Xcode
2. Set your development team in Signing & Capabilities
3. Build and run on a simulator or device
4. Go to **Settings** in the app and enter your [Claude API key](https://console.anthropic.com/settings/keys)
5. Tap **Test API Key** to verify it works
6. Go to the **Scan** tab and take a photo of your fridge

## Project Structure

```
FridgeCheck/
├── Models/          # SwiftData models (Recipe, PantryItem, MealPlan, etc.)
├── Services/        # Claude API client and camera/photo helpers
├── ViewModels/      # Observable view models for each feature
├── Views/           # SwiftUI views organized by feature
│   ├── Home/        # Dashboard with recent scans and today's meals
│   ├── Scan/        # Camera capture → ingredient detection → recipe suggestions
│   ├── Pantry/      # Ingredient inventory with expiry tracking
│   ├── Recipes/     # Browse, search, and filter saved recipes
│   ├── ShoppingList/# Checkable shopping list with pantry integration
│   ├── MealPlan/    # Weekly meal calendar
│   └── Settings/    # API key, dietary preferences, allergies
└── Utilities/       # Date formatting and color helpers
```

## Requirements

- Xcode 15+
- iOS 17+
- A [Claude API key](https://console.anthropic.com/settings/keys) with active billing
