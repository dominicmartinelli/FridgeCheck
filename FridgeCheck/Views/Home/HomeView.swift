import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.date, order: .reverse) private var recentScans: [ScanRecord]
    @Query(sort: \MealPlan.date) private var mealPlans: [MealPlan]
    @Query private var pantryItems: [PantryItem]

    private var todaysMeals: [MealPlan] {
        let calendar = Calendar.current
        return mealPlans.filter { calendar.isDateInToday($0.date) }
            .sorted { $0.mealType < $1.mealType }
    }

    private var expiringItems: [PantryItem] {
        pantryItems.filter { $0.isExpiringSoon || $0.isExpired }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Quick scan button
                    quickScanSection

                    // Today's meal plan
                    if !todaysMeals.isEmpty {
                        todaysMealSection
                    }

                    // Expiry warnings
                    if !expiringItems.isEmpty {
                        expiryWarningSection
                    }

                    // Recent scans
                    if !recentScans.isEmpty {
                        recentScansSection
                    }

                    // Stats
                    statsSection
                }
                .padding()
            }
            .navigationTitle("Fridge Check")
        }
    }

    // MARK: - Quick Scan

    private var quickScanSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Your Fridge")
                        .font(.headline)
                    Text("Take a photo to identify ingredients and get recipe ideas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.1))
            )
        }
    }

    // MARK: - Today's Meals

    private var todaysMealSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's Meals", systemImage: "fork.knife")
                .font(.headline)

            ForEach(todaysMeals) { meal in
                HStack(spacing: 12) {
                    Text(meal.mealType)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 80, alignment: .leading)

                    if let recipe = meal.recipe {
                        Text(recipe.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No recipe planned")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Expiry Warnings

    private var expiryWarningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Expiring Soon", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(expiringItems) { item in
                HStack {
                    Circle()
                        .fill(item.isExpired ? Color.expiryRed : Color.expiryYellow)
                        .frame(width: 8, height: 8)

                    Text(item.name)
                        .font(.subheadline)

                    Spacer()

                    if let expiry = item.expiryDate {
                        Text(expiry.formatted_relative)
                            .font(.caption)
                            .foregroundStyle(item.isExpired ? .red : .orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Recent Scans

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Scans", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(recentScans.prefix(5))) { scan in
                        VStack(spacing: 8) {
                            if let uiImage = UIImage(data: scan.imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            VStack(spacing: 2) {
                                Text("\(scan.detectedIngredients.count) items")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(scan.date.formatted_relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Overview", systemImage: "chart.bar")
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(title: "Pantry Items", value: "\(pantryItems.count)", icon: "basket.fill", color: .green)
                StatCard(title: "Scans", value: "\(recentScans.count)", icon: "camera.fill", color: .blue)
                StatCard(title: "Meals Planned", value: "\(mealPlans.count)", icon: "calendar", color: .purple)
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [
            UserPreferences.self, PantryItem.self, Recipe.self,
            ScanRecord.self, MealPlan.self
        ], inMemory: true)
}
