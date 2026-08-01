//
//  ImageQualityAnalyzer.swift
//  MtPoseCameraDemo26
//
//  Phân tích metadata & chất lượng ảnh để so sánh giữa:
//  - Frame cắt ra từ video (đã trải qua nén video H.264/HEVC)
//  - Ảnh chụp trực tiếp bằng camera (JPEG/HEIC nén 1 lần, không qua nén video)
//

import UIKit
import ImageIO
import CoreGraphics

struct ImageQualityReport {
    let pixelWidth: Int
    let pixelHeight: Int
    let megapixels: Double
    let aspectRatio: String
    
    let colorSpaceName: String
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let hasAlpha: Bool
    
    let jpegSizeBytes: Int      // xuất JPEG quality = 1.0
    let pngSizeBytes: Int       // xuất PNG (lossless)
    let bytesPerMegapixelJPEG: Double
    
    /// Dung lượng file gốc lúc import (nếu có) — khác với jpegSizeBytes vì đây là dữ liệu
    /// gốc chưa qua re-encode. nil nếu không xác định được (ví dụ ảnh lấy từ video frame).
    let originalFileSizeBytes: Int?
    
    // So sánh định tính với ảnh chụp camera thật
    let cameraEquivalenceVerdict: String
    let cameraEquivalenceDetail: String
    
    var summaryLines: [(String, String)] {
        var lines: [(String, String)] = [
            ("Kích thước", "\(pixelWidth) x \(pixelHeight) px"),
            ("Độ phân giải", String(format: "%.2f MP", megapixels)),
            ("Tỉ lệ khung hình", aspectRatio),
            ("Color space", colorSpaceName),
            ("Bit / thành phần màu", "\(bitsPerComponent) bit"),
            ("Bit / pixel", "\(bitsPerPixel) bit"),
            ("Alpha channel", hasAlpha ? "Có" : "Không")
        ]
        if let originalFileSizeBytes {
            lines.append(("Dung lượng file gốc", formatBytes(originalFileSizeBytes)))
        }
        lines.append(("Dung lượng JPEG (Q=100%)", formatBytes(jpegSizeBytes)))
        lines.append(("Dung lượng PNG (lossless)", formatBytes(pngSizeBytes)))
        lines.append(("Mật độ dữ liệu", String(format: "%.0f KB/MP (JPEG)", bytesPerMegapixelJPEG / 1024)))
        return lines
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes > 1_000_000 {
            return String(format: "%.2f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

/// Kết quả so sánh giữa 2 ảnh bất kỳ (dùng cho tab Compare Images)
struct ImageComparisonResult {
    let resolutionWinner: String
    let fileSizeWinner: String
    let bitDepthNote: String
    let colorSpaceNote: String
    let overallNote: String
}

enum ImageQualityAnalyzer {
    
    /// Ngưỡng tham chiếu "mật độ dữ liệu" điển hình của ảnh chụp camera JPEG chất lượng cao
    /// (khoảng 1.2 - 2.5 MB/MP tùy máy). Dùng để đưa ra nhận định định tính, KHÔNG phải con số tuyệt đối.
    private static let typicalCameraKBPerMP: ClosedRange<Double> = 1200...2600
    
    static func analyze(_ image: UIImage, originalFileSizeBytes: Int? = nil) -> ImageQualityReport {
        guard let cgImage = image.cgImage else {
            return ImageQualityReport(
                pixelWidth: 0, pixelHeight: 0, megapixels: 0, aspectRatio: "-",
                colorSpaceName: "Không xác định", bitsPerComponent: 0, bitsPerPixel: 0, hasAlpha: false,
                jpegSizeBytes: 0, pngSizeBytes: 0, bytesPerMegapixelJPEG: 0,
                originalFileSizeBytes: originalFileSizeBytes,
                cameraEquivalenceVerdict: "Không xác định",
                cameraEquivalenceDetail: "Không đọc được dữ liệu ảnh."
            )
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let megapixels = Double(width * height) / 1_000_000.0
        let aspect = aspectRatioString(width, height)
        
        let colorSpaceName = (cgImage.colorSpace?.name as String?) ?? "Không xác định (device-dependent)"
        let bpc = cgImage.bitsPerComponent
        let bpp = cgImage.bitsPerPixel
        let alphaInfo = cgImage.alphaInfo
        let hasAlpha = !(alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)
        
        let jpegData = image.jpegData(compressionQuality: 1.0)
        let pngData = image.pngData()
        let jpegBytes = jpegData?.count ?? 0
        let pngBytes = pngData?.count ?? 0
        
        let bytesPerMP = megapixels > 0 ? Double(jpegBytes) / megapixels : 0
        let kbPerMP = bytesPerMP / 1024
        
        let (verdict, detail) = evaluateCameraEquivalence(kbPerMP: kbPerMP, megapixels: megapixels)
        
        return ImageQualityReport(
            pixelWidth: width,
            pixelHeight: height,
            megapixels: megapixels,
            aspectRatio: aspect,
            colorSpaceName: colorSpaceName,
            bitsPerComponent: bpc,
            bitsPerPixel: bpp,
            hasAlpha: hasAlpha,
            jpegSizeBytes: jpegBytes,
            pngSizeBytes: pngBytes,
            bytesPerMegapixelJPEG: bytesPerMP,
            originalFileSizeBytes: originalFileSizeBytes,
            cameraEquivalenceVerdict: verdict,
            cameraEquivalenceDetail: detail
        )
    }
    
    /// So sánh 2 report bất kỳ (dùng cho tab Compare Images) — trả về nhận định
    /// định tính giữa 2 ảnh, không giả định ảnh nào là "chuẩn".
    static func compare(_ a: ImageQualityReport, _ b: ImageQualityReport, nameA: String = "Ảnh 1", nameB: String = "Ảnh 2") -> ImageComparisonResult {
        let resolutionWinner: String
        if a.megapixels > b.megapixels * 1.02 {
            resolutionWinner = "\(nameA) có độ phân giải cao hơn (\(String(format: "%.2f", a.megapixels)) MP so với \(String(format: "%.2f", b.megapixels)) MP)"
        } else if b.megapixels > a.megapixels * 1.02 {
            resolutionWinner = "\(nameB) có độ phân giải cao hơn (\(String(format: "%.2f", b.megapixels)) MP so với \(String(format: "%.2f", a.megapixels)) MP)"
        } else {
            resolutionWinner = "Độ phân giải gần như tương đương nhau"
        }
        
        let fileSizeWinner: String
        let sizeA = a.originalFileSizeBytes ?? a.jpegSizeBytes
        let sizeB = b.originalFileSizeBytes ?? b.jpegSizeBytes
        if sizeA > 0 && sizeB > 0 {
            let ratio = Double(max(sizeA, sizeB)) / Double(min(sizeA, sizeB))
            let biggerName = sizeA > sizeB ? nameA : nameB
            if ratio < 1.1 {
                fileSizeWinner = "Dung lượng file gần như tương đương nhau"
            } else {
                fileSizeWinner = "\(biggerName) có dung lượng lớn hơn khoảng \(String(format: "%.1f", ratio))x — thường phản ánh nén ít hơn hoặc nhiều chi tiết hơn"
            }
        } else {
            fileSizeWinner = "Không đủ dữ liệu để so sánh dung lượng"
        }
        
        let bitDepthNote: String
        if a.bitsPerPixel == b.bitsPerPixel {
            bitDepthNote = "Cùng độ sâu màu (\(a.bitsPerPixel) bit/pixel)"
        } else {
            bitDepthNote = "\(nameA): \(a.bitsPerPixel) bit/pixel — \(nameB): \(b.bitsPerPixel) bit/pixel (ảnh có bit/pixel cao hơn thường lưu được nhiều sắc độ màu hơn)"
        }
        
        let colorSpaceNote: String
        if a.colorSpaceName == b.colorSpaceName {
            colorSpaceNote = "Cùng color space (\(a.colorSpaceName))"
        } else {
            colorSpaceNote = "\(nameA): \(a.colorSpaceName) — \(nameB): \(b.colorSpaceName) (khác color space có thể dẫn đến khác biệt màu sắc khi hiển thị/so sánh trực tiếp)"
        }
        
        let overallNote: String
        if abs(a.megapixels - b.megapixels) / max(a.megapixels, b.megapixels, 0.001) < 0.02 &&
            a.bitsPerPixel == b.bitsPerPixel {
            overallNote = "Hai ảnh có thông số kỹ thuật (độ phân giải, độ sâu màu) gần như tương đương. Chênh lệch dung lượng file (nếu có) chủ yếu đến từ mức độ nén hoặc nội dung chi tiết trong khung hình, không hẳn phản ánh chất lượng nguồn khác nhau."
        } else {
            overallNote = "Hai ảnh khác nhau về thông số kỹ thuật — nên cân nhắc đưa về cùng độ phân giải/color space trước khi so sánh trực quan để tránh đánh giá sai lệch do khác nguồn gốc xử lý."
        }
        
        return ImageComparisonResult(
            resolutionWinner: resolutionWinner,
            fileSizeWinner: fileSizeWinner,
            bitDepthNote: bitDepthNote,
            colorSpaceNote: colorSpaceNote,
            overallNote: overallNote
        )
    }
    
    private static func evaluateCameraEquivalence(kbPerMP: Double, megapixels: Double) -> (String, String) {
        var detail = """
        Frame trích từ video luôn đi qua bộ mã hóa video (H.264/HEVC), vốn dùng nén \
        chroma subsampling 4:2:0 và bitrate được tối ưu cho phát lại mượt (playback), \
        không phải cho độ chi tiết tối đa như ảnh chụp tĩnh (JPEG/HEIC nén 1 lần, thường \
        chroma 4:2:2 hoặc 4:4:4). Vì vậy, dù đã trích ở độ phân giải gốc và không xử lý \
        thêm, ảnh vẫn có ít chi tiết cạnh/nhiễu mịn hơn so với ảnh chụp cùng khung hình.
        """
        
        let verdict: String
        if kbPerMP >= typicalCameraKBPerMP.lowerBound {
            verdict = "Gần tương đương"
            detail += "\n\nMật độ dữ liệu (KB/MP) nằm trong khoảng thường thấy ở ảnh chụp camera, cho thấy video được quay ở bitrate cao — nhưng đây chỉ là proxy, không đảm bảo độ sắc nét/chi tiết thực tế bằng nhau."
        } else if kbPerMP >= typicalCameraKBPerMP.lowerBound * 0.4 {
            verdict = "Thấp hơn ảnh chụp thật"
            detail += "\n\nMật độ dữ liệu thấp hơn đáng kể so với ảnh chụp camera thông thường — dấu hiệu bitrate video không đủ cao để giữ chi tiết tương đương ảnh tĩnh."
        } else {
            verdict = "Kém xa ảnh chụp thật"
            detail += "\n\nMật độ dữ liệu rất thấp so với ảnh chụp — video có khả năng bị nén mạnh (bitrate thấp, độ phân giải thấp, hoặc frame bị motion blur), chất lượng KHÔNG tương đương ảnh chụp trực tiếp."
        }
        
        return (verdict, detail)
    }
    
    private static func aspectRatioString(_ w: Int, _ h: Int) -> String {
        guard w > 0, h > 0 else { return "-" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(w, h)
        guard g > 0 else { return "-" }
        return "\(w / g):\(h / g)"
    }
}
