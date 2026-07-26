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
    // MARK: - Published Properties (Import / Preview)
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
    @Published var isLoadingVideo = false
    
    // MARK: - Published Properties (Extraction)
    @Published var extractedImages: [UIImage] = []
    @Published var selectedFrameIndex: Float = 0
    @Published var isLoading = false
    @Published var extractionProgress: Float?
    @Published var extractionMode: ExtractionMode = .all
    @Published var extractInterval: TimeInterval = 1.0
    
    // MARK: - Published Properties (Analyze)
    @Published var isAnalyzing = false
    @Published var rawFrameImage: UIImage?
    @Published var optimizedFrameImage: UIImage?
    @Published var rawReport: ImageQualityReport?
    @Published var optimizedReport: ImageQualityReport?
    
    // MARK: - Error handling
    @Published var showError = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var selectedImage: UIImage? {
        guard !extractedImages.isEmpty else { return nil }
        let index = Int(selectedFrameIndex)
        return extractedImages.indices.contains(index) ? extractedImages[index] : nil
    }
    
    /// Thời điểm (giây) tương ứng với vị trí slider hiện tại, dựa theo khoảng interval đã dùng để extract.
    var currentSelectedTime: TimeInterval {
        TimeInterval(selectedFrameIndex) * extractInterval
    }
    
    // MARK: - Private Properties
    private let extractor = VideoExtractor()
    
    // MARK: - Load Video
    
    func loadVideo() async {
        guard let selectedVideo = selectedVideo else { return }
        
        isLoadingVideo = true
        // Reset toàn bộ state cũ khi chọn video mới
        extractedImages = []
        selectedFrameIndex = 0
        extractionProgress = nil
        rawFrameImage = nil
        optimizedFrameImage = nil
        rawReport = nil
        optimizedReport = nil
        
        do {
            guard let data = try await selectedVideo.loadTransferable(type: Data.self) else {
                throw NSError(domain: "VideoLoader", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Cannot load video data"])
            }
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            try data.write(to: tempURL)
            
            self.videoURL = tempURL
            self.videoName = selectedVideo.itemIdentifier ?? tempURL.lastPathComponent
            self.player = AVPlayer(url: tempURL)
            self.isLoadingVideo = false
            self.player?.play()
            
        } catch {
            self.isLoadingVideo = false
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
        clearAnalysis()
        
        do {
            let images = try await extractor.extractAll(
                videoUrl: videoURL,
                at: extractInterval
            )
            
            self.extractedImages = images
            self.selectedFrameIndex = 0
            self.isLoading = false
            
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
        clearAnalysis()
        
        do {
            let images = try await extractor.extractWithProgress(
                videoUrl: videoURL,
                at: extractInterval
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.extractionProgress = progress
                }
            }
            
            self.extractedImages = images
            self.selectedFrameIndex = 0
            self.isLoading = false
            self.extractionProgress = 1.0
            
        } catch {
            self.isLoading = false
            self.extractionProgress = nil
            showError(message: error.localizedDescription)
        }
    }
    
    // MARK: - Analyze
    
    /// Lấy frame tại đúng thời điểm slider hiện tại, tạo 2 bản (raw & optimized),
    /// rồi phân tích metadata/chất lượng của cả hai để so sánh.
    func analyzeCurrentFrame() async {
        guard let videoURL = videoURL else {
            showError(message: "No video selected")
            return
        }
        guard !extractedImages.isEmpty else {
            showError(message: "Chưa có frame nào được extract")
            return
        }
        
        isAnalyzing = true
        
        do {
            async let raw = extractor.extractRawFrame(videoUrl: videoURL, at: currentSelectedTime)
            async let optimized = extractor.extractSingleFrame(videoUrl: videoURL, at: currentSelectedTime)
            
            let (rawImage, optimizedImage) = try await (raw, optimized)
            
            self.rawFrameImage = rawImage
            self.optimizedFrameImage = optimizedImage
            self.rawReport = ImageQualityAnalyzer.analyze(rawImage)
            self.optimizedReport = ImageQualityAnalyzer.analyze(optimizedImage)
            self.isAnalyzing = false
            
        } catch {
            self.isAnalyzing = false
            showError(message: "Analyze thất bại: \(error.localizedDescription)")
        }
    }
    
    private func clearAnalysis() {
        rawFrameImage = nil
        optimizedFrameImage = nil
        rawReport = nil
        optimizedReport = nil
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
