//
//  PoseOverlayCanvas.swift
//  MtPoseCameraDemo26
//
//  View vẽ skeleton (body joints) + face landmarks đè lên ảnh/preview.
//  Dùng chung cho cả tab phân tích ảnh tĩnh và tab tracking camera trực tiếp.
//
//  Quy ước màu theo độ tin cậy (confidence) — vì Vision KHÔNG có cờ "isOccluded"
//  rõ ràng, điểm có confidence thấp thường tương ứng với khớp bị khuất/mơ hồ,
//  nhưng model vẫn trả về toạ độ ước lượng cho điểm đó → ta vẫn vẽ được.
//

import SwiftUI
import Vision

struct PoseOverlayCanvas: View {
    let joints: [BodyJointPoint]
    let faceLandmarkGroups: [FaceLandmarkGroup]
    var showLowConfidencePoints: Bool = true
    var lowConfidenceThreshold: Float = 0.3
    
    var body: some View {
        Canvas { context, size in
            let jointsByName = Dictionary(uniqueKeysWithValues: joints.map { ($0.jointName, $0) })
            
            // Vẽ skeleton (đường nối giữa các khớp)
            for (a, b) in PoseVisionHelper.skeletonConnections {
                guard let jointA = jointsByName[a], let jointB = jointsByName[b] else { continue }
                let minConfidence = min(jointA.confidence, jointB.confidence)
                if !showLowConfidencePoints && minConfidence < lowConfidenceThreshold { continue }
                
                var path = Path()
                path.move(to: convert(jointA.location, size: size))
                path.addLine(to: convert(jointB.location, size: size))
                
                context.stroke(
                    path,
                    with: .color(color(for: minConfidence).opacity(minConfidence < lowConfidenceThreshold ? 0.5 : 0.9)),
                    style: StrokeStyle(
                        lineWidth: 3,
                        dash: minConfidence < lowConfidenceThreshold ? [6, 4] : []
                    )
                )
            }
            
            // Vẽ từng điểm khớp cơ thể
            for joint in joints {
                if !showLowConfidencePoints && joint.confidence < lowConfidenceThreshold { continue }
                drawDot(context: &context, at: convert(joint.location, size: size), radius: 6, color: color(for: joint.confidence))
            }
            
            // Vẽ landmark khuôn mặt (chấm nhỏ hơn, màu cyan)
            for group in faceLandmarkGroups {
                for point in group.points {
                    drawDot(context: &context, at: convert(point, size: size), radius: 1.6, color: .cyan)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func drawDot(context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
    
    /// Vision dùng hệ toạ độ normalized với gốc ở GÓC DƯỚI-TRÁI, còn SwiftUI Canvas gốc ở GÓC TRÊN-TRÁI
    /// → cần lật trục Y.
    private func convert(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }
    
    private func color(for confidence: Float) -> Color {
        if confidence > 0.5 { return .green }        // rõ ràng, đáng tin cậy
        if confidence > lowConfidenceThreshold { return .orange } // không chắc chắn
        return .red                                   // rất thấp — nhiều khả năng bị khuất, chỉ là ước lượng
    }
}
