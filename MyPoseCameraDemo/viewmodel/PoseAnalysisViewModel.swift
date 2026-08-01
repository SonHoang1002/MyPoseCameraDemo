//
//  PoseAnalysisViewModel.swift
//  MtPoseCameraDemo26
//
//  Import 1 ảnh, chạy Vision để lấy: body pose 2D, body pose 3D (nếu khả dụng),
//  face landmarks chi tiết, feature print (để so ảnh mẫu), và đánh giá chất lượng/
//  độ tin cậy của khung hình (blur, vị trí có bị cắt mép hay không).
//

import SwiftUI
import PhotosUI
import Vision
internal import Combine

@MainActor
final class PoseAnalysisViewModel: ObservableObject {
    @Published var selectedItem: PhotosPickerItem? {
        didSet { Task { await loadAndAnalyze() } }
    }
    
    @Published var image: UIImage?
    /// Kích thước PIXEL THỰC của ảnh — dùng để so pose bất biến với tỉ lệ khung hình.
    @Published var imageSize: CGSize = .zero
    @Published var isAnalyzing = false
    
    @Published var bodyJoints2D: [BodyJointPoint] = []
    @Published var body3DJoints: [Body3DJointInfo] = []
    @Published var faceLandmarkGroups: [FaceLandmarkGroup] = []
    @Published var featurePrint: VNFeaturePrintObservation?
    @Published var frameQuality: FrameReliabilityReport?
    
    @Published var showLowConfidencePoints = true
    
    @Published var showError = false
    @Published var errorMessage: String?
    
    var hasBody: Bool { !bodyJoints2D.isEmpty }
    var has3DBody: Bool { !body3DJoints.isEmpty }
    var hasFace: Bool { !faceLandmarkGroups.isEmpty }
    
    func loadAndAnalyze() async {
        guard let selectedItem else { return }
        
        isAnalyzing = true
        bodyJoints2D = []
        body3DJoints = []
        faceLandmarkGroups = []
        featurePrint = nil
        frameQuality = nil
        
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                throw NSError(domain: "PoseAnalysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không đọc được ảnh"])
            }
            
            self.image = uiImage
            
            guard let cgImage = uiImage.cgImage else {
                throw NSError(domain: "PoseAnalysis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ảnh không hợp lệ"])
            }
            
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            self.imageSize = size
            let orientation = PoseVisionHelper.cgOrientation(from: uiImage.imageOrientation)
            
            // Chạy Vision trên background thread để không chặn UI
            let (result, fp, blur) = await Task.detached(priority: .userInitiated) {
                let poseResult = PoseVisionHelper.analyze(cgImage: cgImage, orientation: orientation)
                let featurePrint = SimilarityHelper.generateFeaturePrint(cgImage: cgImage, orientation: orientation)
                let blur = FrameQualityAnalyzer.analyzeBlur(cgImage: cgImage)
                return (poseResult, featurePrint, blur)
            }.value
            
            self.bodyJoints2D = result.bodyJoints2D
            self.body3DJoints = result.body3DJoints
            self.faceLandmarkGroups = result.faceLandmarkGroups
            self.featurePrint = fp
            self.frameQuality = FrameQualityAnalyzer.buildReliabilityReport(
                imageSize: size,
                joints: result.bodyJoints2D,
                blur: blur
            )
            self.isAnalyzing = false
            
        } catch {
            self.isAnalyzing = false
            errorMessage = "Phân tích thất bại: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func reset() {
        selectedItem = nil
        image = nil
        imageSize = .zero
        bodyJoints2D = []
        body3DJoints = []
        faceLandmarkGroups = []
        featurePrint = nil
        frameQuality = nil
    }
}
