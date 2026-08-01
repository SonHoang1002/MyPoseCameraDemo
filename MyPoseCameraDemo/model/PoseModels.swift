//
//  PoseModels.swift
//  MtPoseCameraDemo26
//
//  Các struct dùng chung cho phân tích pose (2D/3D) và face landmarks,
//  dùng chung giữa tab "Pose Analysis" (ảnh tĩnh) và tab "Live Pose Tracking" (camera).
//

import Vision
import CoreGraphics
import simd
import UIKit

/// 1 điểm khớp cơ thể (2D), giữ nguyên JointName gốc để còn dùng dựng skeleton.
struct BodyJointPoint: Identifiable {
    let id = UUID()
    let jointName: VNHumanBodyPoseObservation.JointName
    let displayName: String
    /// Toạ độ normalized theo hệ Vision (gốc DƯỚI-TRÁI, 0...1)
    let location: CGPoint
    let confidence: Float
}

/// 1 điểm khớp cơ thể trong không gian 3D (mét), tương đối so với joint gốc (root/hip).
/// Lưu ý: VNHumanBodyRecognizedPoint3D KHÔNG có thuộc tính confidence (khác với điểm 2D),
/// nên report 3D này chỉ có toạ độ, không có độ tin cậy.
struct Body3DJointInfo: Identifiable {
    let id = UUID()
    let displayName: String
    let x: Float
    let y: Float
    let z: Float
    
    var summaryValue: String {
        String(format: "(%.2f, %.2f, %.2f) m", x, y, z)
    }
}

/// 1 nhóm điểm landmark khuôn mặt (ví dụ: mắt trái, môi ngoài, viền mặt...)
struct FaceLandmarkGroup: Identifiable {
    let id = UUID()
    let name: String
    /// Toạ độ normalized theo TOÀN BỘ ảnh (đã quy đổi từ hệ toạ độ cục bộ trong boundingBox của khuôn mặt)
    let points: [CGPoint]
    var count: Int { points.count }
}

/// Kết quả phân tích 1 ảnh: body 2D, body 3D (nếu có), face landmarks (nếu có)
struct PoseAnalysisResult {
    var bodyJoints2D: [BodyJointPoint] = []
    var body3DJoints: [Body3DJointInfo] = []
    var faceLandmarkGroups: [FaceLandmarkGroup] = []
    var hasBody: Bool { !bodyJoints2D.isEmpty }
    var has3DBody: Bool { !body3DJoints.isEmpty }
    var hasFace: Bool { !faceLandmarkGroups.isEmpty }
}

// MARK: - Phân tích chi tiết từng điểm (so với ảnh mẫu + vị trí trong khung hình)

/// Kết quả so sánh của 1 khớp cụ thể so với ảnh mẫu.
struct JointComparisonDetail: Identifiable {
    let id = UUID()
    let jointName: VNHumanBodyPoseObservation.JointName
    let displayName: String
    
    /// % lệch so với ảnh mẫu (0 = trùng khớp hoàn toàn, càng cao càng lệch nhiều). nil nếu thiếu dữ liệu.
    let deviationPercent: Double?
    /// % khớp = 100 - deviationPercent, để hiển thị trực quan hơn (càng cao càng giống ảnh mẫu).
    var matchPercent: Double? { deviationPercent.map { max(0, min(100, 100 - $0)) } }
    
    let currentConfidence: Float
    let referenceConfidence: Float
    
    /// Vị trí trong khung hình HIỆN TẠI có "an toàn" hay không (không sát mép, confidence đủ cao).
    let isPositionValidInFrame: Bool
    let positionWarning: String?
}

/// 1 nhóm bộ phận cơ thể (gộp các khớp liên quan để hiển thị gọn hơn, ví dụ "Chân trái" = hông trái + gối trái + cổ chân trái).
struct BodyPartGroupComparison: Identifiable {
    let id = UUID()
    let groupName: String
    let icon: String
    let joints: [JointComparisonDetail]
    
    /// % khớp trung bình của cả nhóm (chỉ tính trên các khớp có đủ dữ liệu).
    var averageMatchPercent: Double? {
        let values = joints.compactMap { $0.matchPercent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    var hasAnyPositionWarning: Bool {
        joints.contains { !$0.isPositionValidInFrame }
    }
}

enum BodyPartGroup {
    /// Gán mỗi khớp vào 1 nhóm bộ phận cơ thể (tên hiển thị tiếng Việt + icon SF Symbols).
    static func groupInfo(for jointName: VNHumanBodyPoseObservation.JointName) -> (groupName: String, icon: String, order: Int) {
        switch jointName {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
            return ("Đầu & Mặt", "person.crop.circle", 0)
        case .neck, .leftShoulder, .rightShoulder:
            return ("Cổ & Vai", "figure.arms.open", 1)
        case .leftElbow, .leftWrist:
            return ("Tay trái", "hand.raised.fill", 2)
        case .rightElbow, .rightWrist:
            return ("Tay phải", "hand.raised.fill", 3)
        case .root, .leftHip, .rightHip:
            return ("Thân & Hông", "figure.stand", 4)
        case .leftKnee, .leftAnkle:
            return ("Chân trái", "figure.walk", 5)
        case .rightKnee, .rightAnkle:
            return ("Chân phải", "figure.walk", 6)
        default:
            return ("Khác", "questionmark.circle", 7)
        }
    }
}

enum PoseVisionHelper {
    
    /// Danh sách các cặp khớp cần nối để vẽ skeleton (dùng JointName trực tiếp, không phụ thuộc string).
    static let skeletonConnections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .leftEye), (.nose, .rightEye),
        (.leftEye, .leftEar), (.rightEye, .rightEar),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
    
    /// Chạy toàn bộ request (body 2D, body 3D nếu khả dụng, face landmarks) trên 1 CGImage.
    static func analyze(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> PoseAnalysisResult {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return performAllRequests(using: handler)
    }
    
    /// Chạy trên 1 CVPixelBuffer (dùng cho luồng video trực tiếp).
    static func analyze(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> PoseAnalysisResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return performAllRequests(using: handler)
    }
    
    private static func performAllRequests(using handler: VNImageRequestHandler) -> PoseAnalysisResult {
        var result = PoseAnalysisResult()
        
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let faceRequest = VNDetectFaceLandmarksRequest()
        var requests: [VNRequest] = [bodyRequest, faceRequest]
        
        var body3DRequest: VNDetectHumanBodyPose3DRequest?
        if #available(iOS 17.0, *) {
            let req = VNDetectHumanBodyPose3DRequest()
            body3DRequest = req
            requests.append(req)
        }
        
        do {
            try handler.perform(requests)
        } catch {
            // Nếu request thất bại (ví dụ: chạy trên simulator không có Neural Engine cho request 3D),
            // vẫn cố gắng trả về những gì đã có, không throw để không crash UI.
            return result
        }
        
        // MARK: Body 2D — lấy TẤT CẢ điểm, kể cả điểm confidence thấp (có thể đang bị khuất)
        if let obs = bodyRequest.results?.first,
           let points = try? obs.recognizedPoints(.all) {
            result.bodyJoints2D = points.map { key, point in
                BodyJointPoint(
                    jointName: key,
                    displayName: "\(key.rawValue)",
                    location: point.location,
                    confidence: point.confidence
                )
            }
        }
        
        // MARK: Body 3D (best-effort — API mới, có thể không khả dụng trên mọi thiết bị/OS)
        if #available(iOS 17.0, *), let body3DRequest, let obs3D = body3DRequest.results?.first {
            var joints3D: [Body3DJointInfo] = []
            for jointName in obs3D.availableJointNames {
                guard let point = try? obs3D.recognizedPoint(jointName) else { continue }
                // point.position là simd_float4x4 (ma trận biến đổi 4x4); phần translation
                // (vị trí x, y, z tính bằng mét) nằm ở cột thứ 4 (columns.3) của ma trận.
                let translation = point.position.columns.3
                joints3D.append(Body3DJointInfo(
                    displayName: "\(jointName)",
                    x: translation.x,
                    y: translation.y,
                    z: translation.z
                ))
            }
            result.body3DJoints = joints3D
        }
        
        // MARK: Face landmarks chi tiết
        if let faceObs = faceRequest.results?.first, let landmarks = faceObs.landmarks {
            let boundingBox = faceObs.boundingBox
            
            func convert(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                guard let region else { return [] }
                return region.normalizedPoints.map { local in
                    CGPoint(
                        x: boundingBox.origin.x + local.x * boundingBox.width,
                        y: boundingBox.origin.y + local.y * boundingBox.height
                    )
                }
            }
            
            let regionList: [(String, VNFaceLandmarkRegion2D?)] = [
                ("Viền mặt", landmarks.faceContour),
                ("Lông mày trái", landmarks.leftEyebrow),
                ("Lông mày phải", landmarks.rightEyebrow),
                ("Mắt trái", landmarks.leftEye),
                ("Mắt phải", landmarks.rightEye),
                ("Đồng tử trái", landmarks.leftPupil),
                ("Đồng tử phải", landmarks.rightPupil),
                ("Sống mũi", landmarks.noseCrest),
                ("Mũi", landmarks.nose),
                ("Môi ngoài", landmarks.outerLips),
                ("Môi trong", landmarks.innerLips),
                ("Đường giữa mặt", landmarks.medianLine)
            ]
            
            result.faceLandmarkGroups = regionList.compactMap { name, region in
                let points = convert(region)
                guard !points.isEmpty else { return nil }
                return FaceLandmarkGroup(name: name, points: points)
            }
        }
        
        return result
    }
    
    /// Quy đổi UIImage.Orientation sang CGImagePropertyOrientation — dùng chung cho mọi nơi cần đọc ảnh import.
    static func cgOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
