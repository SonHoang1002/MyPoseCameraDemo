//
//  FrameQualityAnalyzer.swift
//  MtPoseCameraDemo26
//
//  Đánh giá "độ tin cậy" của 1 frame/ảnh trước khi dùng để so sánh:
//  1) Độ nét (blur detection) — dùng Laplacian variance, một kỹ thuật CV cổ điển,
//     KHÔNG dùng ML, nên chạy nhanh và không phụ thuộc thiết bị/OS.
//  2) Vị trí trong khung hình có bị cắt/khuất do đứng sát mép, zoom quá gần, v.v.
//  3) Tỉ lệ khung hình (aspect ratio) thực tế của frame — vì camera có thể zoom,
//     người dùng có thể crop, nên tỉ lệ khung hình KHÔNG đảm bảo giống ảnh mẫu.
//
//  QUAN TRỌNG VỀ ĐỘ TIN CẬY: các ngưỡng số (variance, khoảng cách mép...) đều là
//  HEURISTIC hiệu chỉnh thủ công, không phải hằng số được Apple xác nhận. Chúng phụ
//  thuộc vào nội dung ảnh, độ phân giải, ánh sáng — dùng để THAM KHẢO, không phải
//  kết luận tuyệt đối.
//

import CoreGraphics
import CoreImage
import CoreVideo
import Vision

struct BlurAnalysis {
    let laplacianVariance: Double
    /// 0-100, heuristic — variance càng cao thì ảnh càng nét.
    let sharpnessScore: Double
    let isLikelyBlurry: Bool
}

struct FrameEdgeWarning {
    let jointDisplayName: String
    let side: String // "trên", "dưới", "trái", "phải"
}

struct FrameReliabilityReport {
    let imageSize: CGSize
    let aspectRatioString: String
    
    let blur: BlurAnalysis?
    let edgeWarnings: [FrameEdgeWarning]
    let visibleJointCount: Int
    let totalJointCount: Int
    
    /// % tổng hợp: kết hợp độ nét + tỉ lệ khớp còn nằm trong vùng an toàn của khung hình + confidence trung bình.
    var overallReliabilityPercent: Double {
        var score: Double = 100
        
        if let blur, blur.isLikelyBlurry {
            score -= 35
        } else if let blur {
            // Trừ nhẹ theo mức độ nét thấp dù chưa tới ngưỡng "blurry"
            score -= max(0, (60 - blur.sharpnessScore) * 0.3)
        }
        
        if totalJointCount > 0 {
            let visibleRatio = Double(visibleJointCount) / Double(totalJointCount)
            score -= (1 - visibleRatio) * 40
        }
        
        score -= Double(edgeWarnings.count) * 5
        
        return max(0, min(100, score))
    }
    
    var verdict: String {
        let percent = overallReliabilityPercent
        if percent >= 75 { return "Đáng tin cậy" }
        if percent >= 45 { return "Cần thận trọng" }
        return "Không đáng tin cậy"
    }
    
    var warningMessages: [String] {
        var messages: [String] = []
        if let blur, blur.isLikelyBlurry {
            messages.append("Ảnh có dấu hiệu bị mờ/nhoè (variance = \(String(format: "%.0f", blur.laplacianVariance))) — kết quả so sánh phía dưới có thể kém chính xác.")
        }
        if !edgeWarnings.isEmpty {
            let names = edgeWarnings.map { "\($0.jointDisplayName) (sát mép \($0.side))" }.joined(separator: ", ")
            messages.append("Một số điểm khớp nằm rất sát mép khung hình, có thể đã bị cắt mất: \(names).")
        }
        if totalJointCount > 0 && visibleJointCount < totalJointCount / 2 {
            messages.append("Chưa tới 50% số khớp cơ thể được phát hiện rõ ràng — có thể do góc chụp, khoảng cách, hoặc cơ thể bị che khuất phần lớn.")
        }
        return messages
    }
}

enum FrameQualityAnalyzer {
    
    private static let sharedCIContext = CIContext()
    
    // MARK: - Blur detection (ảnh tĩnh)
    
    static func analyzeBlur(cgImage: CGImage, maxDimension: Int = 220) -> BlurAnalysis? {
        guard let gray = grayscalePixels(from: cgImage, maxDimension: maxDimension) else { return nil }
        let variance = laplacianVariance(pixels: gray.pixels, width: gray.width, height: gray.height)
        return buildBlurAnalysis(variance: variance)
    }
    
    // MARK: - Blur detection (frame video / CVPixelBuffer)
    
    static func analyzeBlur(pixelBuffer: CVPixelBuffer, maxDimension: Int = 220) -> BlurAnalysis? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return analyzeBlur(cgImage: cgImage, maxDimension: maxDimension)
    }
    
    private static func buildBlurAnalysis(variance: Double) -> BlurAnalysis {
        // Ngưỡng heuristic: hiệu chỉnh thô dựa trên ảnh thực tế thông thường (220px cạnh dài).
        let sharpnessScore = max(0, min(100, (variance / 12.0)))
        let isBlurry = variance < 60
        return BlurAnalysis(laplacianVariance: variance, sharpnessScore: sharpnessScore, isLikelyBlurry: isBlurry)
    }
    
    private static func grayscalePixels(from cgImage: CGImage, maxDimension: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        guard originalWidth > 0, originalHeight > 0 else { return nil }
        
        let scale = Double(maxDimension) / Double(max(originalWidth, originalHeight))
        let effectiveScale = min(1.0, scale)
        let width = max(3, Int(Double(originalWidth) * effectiveScale))
        let height = max(3, Int(Double(originalHeight) * effectiveScale))
        
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }
    
    private static func laplacianVariance(pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        
        var sum: Double = 0
        var sumSquares: Double = 0
        var count = 0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let up = Double(pixels[(y - 1) * width + x])
                let down = Double(pixels[(y + 1) * width + x])
                let left = Double(pixels[y * width + (x - 1)])
                let right = Double(pixels[y * width + (x + 1)])
                let laplacian = up + down + left + right - 4 * center
                
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        let variance = (sumSquares / Double(count)) - (mean * mean)
        return max(0, variance)
    }
    
    // MARK: - Kiểm tra khớp có sát mép khung hình (khả năng bị cắt) hay không
    
    static func edgeWarnings(for joints: [BodyJointPoint], margin: CGFloat = 0.04, minConfidence: Float = 0.2) -> [FrameEdgeWarning] {
        var warnings: [FrameEdgeWarning] = []
        for joint in joints {
            guard joint.confidence >= minConfidence else { continue }
            let p = joint.location // normalized, gốc dưới-trái theo Vision
            if p.y > 1 - margin {
                warnings.append(FrameEdgeWarning(jointDisplayName: joint.displayName, side: "trên"))
            }
            if p.y < margin {
                warnings.append(FrameEdgeWarning(jointDisplayName: joint.displayName, side: "dưới"))
            }
            if p.x < margin {
                warnings.append(FrameEdgeWarning(jointDisplayName: joint.displayName, side: "trái"))
            }
            if p.x > 1 - margin {
                warnings.append(FrameEdgeWarning(jointDisplayName: joint.displayName, side: "phải"))
            }
        }
        return warnings
    }
    
    // MARK: - Tổng hợp report đầy đủ
    
    static func buildReliabilityReport(
        imageSize: CGSize,
        joints: [BodyJointPoint],
        blur: BlurAnalysis?,
        visibleConfidenceThreshold: Float = 0.3
    ) -> FrameReliabilityReport {
        let warnings = edgeWarnings(for: joints)
        let visibleCount = joints.filter { $0.confidence >= visibleConfidenceThreshold }.count
        
        let gcdValue = gcd(Int(imageSize.width.rounded()), Int(imageSize.height.rounded()))
        let aspectString: String
        if gcdValue > 0, imageSize.width > 0, imageSize.height > 0 {
            aspectString = "\(Int(imageSize.width) / gcdValue):\(Int(imageSize.height) / gcdValue)"
        } else {
            aspectString = "-"
        }
        
        return FrameReliabilityReport(
            imageSize: imageSize,
            aspectRatioString: aspectString,
            blur: blur,
            edgeWarnings: warnings,
            visibleJointCount: visibleCount,
            totalJointCount: joints.count
        )
    }
    
    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
