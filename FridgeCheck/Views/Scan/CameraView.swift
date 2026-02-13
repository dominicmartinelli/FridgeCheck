import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var viewModel = ScanViewModel()
    @State private var showCameraPicker = false
    @State private var showPhotoPicker = false
    @State private var navigateToResults = false

    private var userPreferences: UserPreferences? {
        preferences.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Camera preview placeholder
                cameraPreviewArea

                // Action buttons
                actionButtons
            }
            .navigationTitle("Scan Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.capturedImage != nil {
                        Button("Reset") {
                            viewModel.reset()
                            navigateToResults = false
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(isPresented: $showCameraPicker, onDismiss: handlePickerDismiss) {
                CameraPicker(image: $viewModel.capturedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker, onDismiss: handlePickerDismiss) {
                PhotoPicker(image: $viewModel.capturedImage)
                    .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $navigateToResults) {
                ScanResultsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Camera Preview Area

    private var cameraPreviewArea: some View {
        ZStack {
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.55)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 80)
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.55)
                    .overlay {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 72, weight: .ultraLight))
                                .foregroundStyle(.secondary)

                            Text("Take a photo of your fridge\nor food items")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text("AI will identify the ingredients for you")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    showCameraPicker = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            if viewModel.capturedImage != nil {
                Button {
                    navigateToResults = true
                } label: {
                    Label("Analyze Image", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.25), value: viewModel.capturedImage != nil)
    }

    // MARK: - Helpers

    private func handlePickerDismiss() {
        if viewModel.capturedImage != nil {
            navigateToResults = true
        }
    }
}

#Preview {
    CameraView()
        .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}
