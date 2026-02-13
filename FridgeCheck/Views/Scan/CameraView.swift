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

                // Photo thumbnails strip
                if !viewModel.capturedImages.isEmpty {
                    photoThumbnailStrip
                }

                // Action buttons
                actionButtons
            }
            .navigationTitle("Scan Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.capturedImages.isEmpty {
                        Button("Reset") {
                            viewModel.reset()
                            navigateToResults = false
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraPicker(images: $viewModel.capturedImages)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(images: $viewModel.capturedImages)
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
            if let lastImage = viewModel.capturedImages.last {
                Image(uiImage: lastImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        Text("\(viewModel.capturedImages.count) photo\(viewModel.capturedImages.count == 1 ? "" : "s")")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                    }
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
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                    .overlay {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 72, weight: .ultraLight))
                                .foregroundStyle(.secondary)

                            Text("Take photos of your fridge\nor food items")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text("Add multiple photos to capture all shelves")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Photo Thumbnail Strip

    private var photoThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.capturedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            withAnimation {
                                viewModel.removeImage(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .offset(x: 5, y: -5)
                    }
                }

                // Add more button
                Button {
                    showCameraPicker = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                        Text("Add")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 70, height: 70)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGray6).opacity(0.5))
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

            if !viewModel.capturedImages.isEmpty {
                Button {
                    navigateToResults = true
                } label: {
                    Label(
                        "Analyze \(viewModel.capturedImages.count) Photo\(viewModel.capturedImages.count == 1 ? "" : "s")",
                        systemImage: "sparkles"
                    )
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.capturedImages.count)
    }
}

#Preview {
    CameraView()
        .modelContainer(for: [UserPreferences.self, PantryItem.self, Recipe.self, ScanRecord.self], inMemory: true)
}
