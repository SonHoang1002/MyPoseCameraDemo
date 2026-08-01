//
//  ReferenceImageStore.swift
//  MtPoseCameraDemo26
//
//  State DÙNG CHUNG cho "ảnh mẫu" (reference image) — chỉ import 1 lần,
//  dùng để so sánh cả ở tab Pose Analysis (ảnh) lẫn tab Live Pose Tracking (video).
//

import SwiftUI
import PhotosUI
import Vision
internal import Combine

@MainActor
final class ReferenceImageStore: ObservableObject {
    @Published var selectedItem: PhotosPickerItem? {
        didSet { Task { await loadAndAnalyze() } }
    }
    
    @Published var image: UIImage?
    /// Kích thước PIXEL THỰC của ảnh mẫu — bắt buộc phải lưu lại vì tỉ lệ khung hình của ảnh mẫu
    /// có thể khác hoàn toàn với ảnh/khung hình sẽ đem ra so sánh sau này (camera zoom, crop, v.v.)
    @Published var imageSize: CGSize = .zero
    
    @Published var isProcessing = false
    
    @Published var featurePrint: VNFeaturePrintObservation?
    @Published var poseResult: PoseAnalysisResult?
    @Published var frameQuality: FrameReliabilityReport?
    
    @Published var showError = false
    @Published var errorMessage: String?
    
    var hasReference: Bool { image != nil }
    var hasReferencePose: Bool { !(poseResult?.bodyJoints2D.isEmpty ?? true) }
    
    func loadAndAnalyze() async {
        guard let selectedItem else { return }
        
        isProcessing = true
        featurePrint = nil
        poseResult = nil
        frameQuality = nil
        
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                throw NSError(domain: "ReferenceImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không đọc được ảnh mẫu"])
            }
            
            self.image = uiImage
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            self.imageSize = size
            let orientation = PoseVisionHelper.cgOrientation(from: uiImage.imageOrientation)
            
            let (fp, pose, blur) = await Task.detached(priority: .userInitiated) {
                let featurePrint = SimilarityHelper.generateFeaturePrint(cgImage: cgImage, orientation: orientation)
                let pose = PoseVisionHelper.analyze(cgImage: cgImage, orientation: orientation)
                let blur = FrameQualityAnalyzer.analyzeBlur(cgImage: cgImage)
                return (featurePrint, pose, blur)
            }.value
            
            self.featurePrint = fp
            self.poseResult = pose
            self.frameQuality = FrameQualityAnalyzer.buildReliabilityReport(
                imageSize: size,
                joints: pose.bodyJoints2D,
                blur: blur
            )
            self.isProcessing = false
            
        } catch {
            self.isProcessing = false
            errorMessage = "Phân tích ảnh mẫu thất bại: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func reset() {
        selectedItem = nil
        image = nil
        imageSize = .zero
        featurePrint = nil
        poseResult = nil
        frameQuality = nil
    }
}
