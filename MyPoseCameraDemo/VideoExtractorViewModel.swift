//
//  VideoExtractorViewModel.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
internal import Combine

enum ExtractionMode {
    case all
    case withProgress
}

@MainActor
class VideoExtractorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedVideo: PhotosPickerItem? {
        didSet {
            Task {
                await loadVideo()
            }
        }
    }
    @Published var videoURL: URL?
    @Published var videoName: String?
    @Published var player: AVPlayer?
    @Published var extractedImages: [UIImage] = []
    @Published var selectedFrameIndex: Float = 0
    @Published var isLoading = false
    @Published var extractionProgress: Float?
    @Published var extractionMode: ExtractionMode = .all
    @Published var extractInterval: TimeInterval = 1.0
    @Published var showError = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var selectedImage: UIImage? {
        guard !extractedImages.isEmpty else { return nil }
        let index = Int(selectedFrameIndex)
        return extractedImages.indices.contains(index) ? extractedImages[index] : nil
    }
    
    // MARK: - Private Properties
    private let extractor = VideoExtractor()
    
    // MARK: - Public Methods
    
    func loadVideo() async {
        guard let selectedVideo = selectedVideo else { return }
        
        do {
            guard let data = try await selectedVideo.loadTransferable(type: Data.self) else {
                throw NSError(domain: "VideoLoader", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Cannot load video data"])
            }
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            try data.write(to: tempURL)
            
            self.videoURL = tempURL
            self.videoName = selectedVideo.itemIdentifier ?? "Video"
            self.player = AVPlayer(url: tempURL)
            self.extractedImages = []
            self.selectedFrameIndex = 0
            self.extractionProgress = nil
            self.player?.play()
            
        } catch {
            self.showError = true
            self.errorMessage = "Failed to load video: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Extract Methods
    
    /// Extract all frames without progress tracking
    func extractAllFrames() async {
        guard let videoURL = videoURL else {
            showError(message: "No video selected")
            return
        }
        
        isLoading = true
        extractionMode = .all
        extractionProgress = nil
        extractedImages = []
        selectedFrameIndex = 0
        
        do {
            let images = try await extractor.extractAll(
                videoUrl: videoURL,
                at: extractInterval
            )
            
            self.extractedImages = images
            self.selectedFrameIndex = 0
            self.isLoading = false
            
            print("✅ Extracted \(images.count) frames (without progress)")
            
        } catch {
            self.isLoading = false
            showError(message: error.localizedDescription)
        }
    }
    
    /// Extract frames with progress tracking
    func extractWithProgress() async {
        guard let videoURL = videoURL else {
            showError(message: "No video selected")
            return
        }
        
        isLoading = true
        extractionMode = .withProgress
        extractionProgress = 0
        extractedImages = []
        selectedFrameIndex = 0
        
        do {
            let images = try await extractor.extractWithProgress(
                videoUrl: videoURL,
                at: extractInterval
            ) { [weak self] progress in
                // Update progress on main thread
                Task { @MainActor in
                    self?.extractionProgress = progress
                }
            }
            
            self.extractedImages = images
            self.selectedFrameIndex = 0
            self.isLoading = false
            self.extractionProgress = 1.0
            
            print("✅ Extracted \(images.count) frames (with progress)")
            
        } catch {
            self.isLoading = false
            self.extractionProgress = nil
            showError(message: error.localizedDescription)
        }
    }
    
    // MARK: - Save Methods
    
    func saveSelectedFrame() {
        guard let image = selectedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    func saveAllFrames() {
        guard !extractedImages.isEmpty else { return }
        
        for image in extractedImages {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    // MARK: - Helpers
    
    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }
}
