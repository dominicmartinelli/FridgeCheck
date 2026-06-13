import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section("Scanning") {
                HelpItem(
                    icon: "camera.viewfinder",
                    title: "How it works",
                    text:"Take or pick up to 15 photos of your fridge, then tap Analyze. We identify ingredients, then generate recipes from the ones you select."
                )
                HelpItem(
                    icon: "15.circle",
                    title: "Photo limit: 15 per scan",
                    text:"Each scan uses up to 15 photos — enough to cover every shelf and drawer. More photos mean slightly longer waits, so skip duplicates. To swap a photo, tap the × on its thumbnail."
                )
                HelpItem(
                    icon: "lightbulb",
                    title: "Tips for good results",
                    text:"Shoot in good light, move items to the front, and capture one shelf at a time for best ingredient detection."
                )
            }

            Section("Daily limits") {
                HelpItem(
                    icon: "gauge.with.dots.needle.33percent",
                    title: "Free usage",
                    text:"5 scans and 20 recipe generations per day. Limits reset every 24 hours."
                )
            }

            Section("Account") {
                HelpItem(
                    icon: "applelogo",
                    title: "Sign in with Apple",
                    text:"Your account is tied to your Apple ID. Sign out from Settings; signing back in restores your pantry and scan history on this device."
                )
                HelpItem(
                    icon: "lock.shield",
                    title: "Privacy",
                    text:"Photos are sent to our server only to identify ingredients, then discarded. We never store your images."
                )
            }

            Section("Preferences") {
                HelpItem(
                    icon: "slider.horizontal.3",
                    title: "Dietary restrictions, allergies, cuisines",
                    text:"Go to the Settings tab to toggle dietary restrictions (e.g. vegetarian, keto), food allergies, and favorite cuisines. Allergies are strictly avoided in recipe suggestions; dietary restrictions and cuisines steer what's generated. Changes apply to your next recipe generation — no save button needed."
                )
                HelpItem(
                    icon: "person.2",
                    title: "Serving size",
                    text:"Also in Settings — use the stepper to set how many people recipes should serve (1–12). Ingredient quantities scale with this number."
                )
            }

            Section("Troubleshooting") {
                HelpItem(
                    icon: "exclamationmark.triangle",
                    title: "Scan says \"Daily limit reached\"",
                    text:"You've used all 5 scans for today. Try again after 24 hours from your first scan."
                )
                HelpItem(
                    icon: "wifi.slash",
                    title: "Scan fails or hangs",
                    text:"Check your internet connection, then try again. If it keeps failing, force-quit and relaunch the app."
                )
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpItem: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { HelpView() }
}
