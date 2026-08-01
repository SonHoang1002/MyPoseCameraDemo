//
//  VideoExtractorViewModel.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI
internal import AVFoundation
import AVKit
import Photos
internal import Combine

@MainActor
class VideoExtractorViewModel: ObservableObject {
    // MARK: - Import / Preview
    @Published var selectedVideo: PhotosPickerItem? {
        didSet {
            Task { await loadVideo() }
        }
    }
    @Published var videoURL: URL?
    @Published var videoName: String?
    @Published var player: AVPlayer?
    @Published var isLoadingVideo = false
    
    // MARK: - Video Info Analysis
    @Published var videoInfoReport: VideoInfoReport?
    @Published var isAnalyzingVideoInfo = false
    
    // MARK: - Extraction
    @Published var extractedImages: [UIImage] = []
    @Published var isExtracting = false
    @Published var extractionProgress: Float?
    @Published var extractInterval: TimeInterval = 1.0
    
    /// Vị trí slider theo % (0.0 -> 1.0) tương ứng với toàn bộ chiều dài video đã extract.
    @Published var sliderPercentage: Float = 0
    
    // MARK: - Save
    @Published var isSaving = false
    
    // MARK: - Error handling
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showSavedToast = false
    
    // MARK: - Computed
    
    var currentIndex: Int {
        guard !extractedImages.isEmpty else { return 0 }
        let lastIndex = extractedImages.count - 1
        let raw = Int((sliderPercentage * Float(lastIndex)).rounded())
        return min(max(raw, 0), lastIndex)
    }
    
    var currentImage: UIImage? {
        guard extractedImages.indices.contains(currentIndex) else { return nil }
        return extractedImages[currentIndex]
    }
    
    var currentTimeLabel: String {
        let time = Double(currentIndex) * extractInterval
        return String(format: "%.1fs", time)
    }
    
    // MARK: - Private
    private let extractor = VideoExtractor()
    
    // MARK: - Load Video
    
    func loadVideo() async {
        guard let selectedVideo = selectedVideo else { return }
        
        isLoadingVideo = true
        extractedImages = []
        sliderPercentage = 0
        extractionProgress = nil
        videoInfoReport = nil
        
        do {
            guard let data = try await selectedVideo.loadTransferable(type: Data.self) else {
                throw NSError(domain: "VideoLoader", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Cannot load video data"])
            }
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            try data.write(to: tempURL)
            
            self.videoURL = tempURL
            self.videoName = tempURL.lastPathComponent
            self.player = AVPlayer(url: tempURL)
            self.isLoadingVideo = false
            self.player?.play()
            
            await analyzeVideoInfo()
            
        } catch {
            self.isLoadingVideo = false
            showError(message: "Failed to load video: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Analyze Video Info
    
    func analyzeVideoInfo() async {
        guard let videoURL = videoURL else { return }
        
        isAnalyzingVideoInfo = true
        do {
            let report = try await VideoInfoAnalyzer.analyze(url: videoURL)
            self.videoInfoReport = report
            self.isAnalyzingVideoInfo = false
        } catch {
            self.isAnalyzingVideoInfo = false
            showError(message: "Phân tích video thất bại: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Extract
    
    func extractVideo() async {
        guard let videoURL = videoURL else {
            showError(message: "Chưa chọn video")
            return
        }
        
        isExtracting = true
        extractionProgress = 0
        extractedImages = []
        sliderPercentage = 0
        
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
            self.sliderPercentage = 0
            self.isExtracting = false
            self.extractionProgress = 1.0
            
        } catch {
            self.isExtracting = false
            self.extractionProgress = nil
            showError(message: error.localizedDescription)
        }
    }
    
    // MARK: - Save to Photos
    
    /// Lưu frame tại vị trí slider hiện tại vào thư viện ảnh.
    /// Dùng PHPhotoLibrary với quyền "Add Only" (không cần quyền đọc toàn bộ thư viện).
    func saveCurrentFrameToPhotos() async {
        guard let image = currentImage else {
            showError(message: "Không có ảnh để lưu")
            return
        }
        
        isSaving = true
        
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSaving = false
            showError(message: "Ứng dụng chưa được cấp quyền lưu ảnh. Vui lòng vào Cài đặt > Quyền riêng tư > Ảnh để bật quyền.")
            return
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
            
            isSaving = false
            showSavedToast = true
            
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showSavedToast = false
            
        } catch {
            isSaving = false
            showError(message: "Lưu ảnh thất bại: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }
}
