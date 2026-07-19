//
//  VideoExtractor.swift
//  MtPoseCameraDemo26
//
//  High-quality frame extraction using AVAssetImageGenerator.
//  Configured to produce frames as close as possible in quality
//  to a real camera capture (full resolution, correct orientation,
//  exact timestamp, no downscaling).
//

import AVFoundation
import UIKit

enum VideoExtractorError: LocalizedError {
    case cannotReadDuration
    case noFramesGenerated
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotReadDuration:
            return "Cannot read video duration"
        case .noFramesGenerated:
            return "No frames were generated"
        case .generationFailed(let msg):
            return "Frame generation failed: \(msg)"
        }
    }
}

final class VideoExtractor {
    
    /// Tạo AVAssetImageGenerator đã được cấu hình để cho chất lượng cao nhất.
    private func makeHighQualityGenerator(for asset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        
        // Không cho phép AVFoundation làm tròn / lấy frame gần đó để tăng tốc.
        // Đảm bảo lấy đúng frame tại thời điểm yêu cầu (chính xác nhất có thể).
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Giữ nguyên độ phân giải gốc của video, không downscale.
        // (mặc định generator có thể tự giảm kích thước để tăng tốc độ xử lý)
        generator.maximumSize = .zero
        
        // Áp dụng transform quay video (video quay dọc/ngang sẽ ra đúng chiều,
        // giống hệt như video hiển thị trong Photos, không bị lệch/xoay sai).
        generator.appliesPreferredTrackTransform = true
        
        // Không dùng chế độ "apertureMode legacy" (crop kiểu cũ) — giữ full frame
        // đúng như dữ liệu gốc được encode trong track video.
        if #available(iOS 16.0, *) {
            generator.apertureMode = .cleanAperture
        } else {
            generator.apertureMode = .encodedPixels
        }
        
        return generator
    }
    
    /// Chuyển CGImage sang UIImage giữ nguyên chất lượng, không nén lại.
    private func makeUIImage(from cgImage: CGImage) -> UIImage {
        // scale = 1 vì đây là ảnh raster thực (pixel-for-pixel), không phải @2x/@3x asset.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
    
    /// Trích toàn bộ frame theo khoảng thời gian `interval`, không có callback progress.
    /// Dùng generateCGImagesAsynchronously theo batch để tránh block quá lâu nhưng vẫn full quality.
    func extractAll(videoUrl: URL, at interval: TimeInterval) async throws -> [UIImage] {
        let asset = AVURLAsset(url: videoUrl)
        
        let durationCMTime = try await asset.load(.duration)
        let duration = durationCMTime.seconds
        guard duration.isFinite, duration > 0 else {
            throw VideoExtractorError.cannotReadDuration
        }
        
        var times: [CMTime] = []
        var t: TimeInterval = 0
        while t < duration {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += interval
        }
        guard !times.isEmpty else { throw VideoExtractorError.noFramesGenerated }
        
        let generator = makeHighQualityGenerator(for: asset)
        
        // Dùng API mới (iOS 16+) trả về ảnh đúng theo thứ tự thời gian yêu cầu.
        var results: [(TimeInterval, UIImage)] = []
        
        if #available(iOS 16.0, *) {
            for await result in generator.images(for: times) {
                switch result {
                case .success(requestedTime: let requested, image: let cgImage, actualTime: _):
                    results.append((requested.seconds, makeUIImage(from: cgImage)))
                case .failure(requestedTime: _, error: let error):
                    // Bỏ qua frame lỗi, tiếp tục các frame còn lại
                    print("⚠️ Failed to generate frame: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback cho iOS < 16
            for time in times {
                do {
                    let cgImage = try await copyCGImage(generator: generator, at: time)
                    results.append((time.seconds, makeUIImage(from: cgImage)))
                } catch {
                    print("⚠️ Failed to generate frame at \(time.seconds)s: \(error.localizedDescription)")
                }
            }
        }
        
        guard !results.isEmpty else { throw VideoExtractorError.noFramesGenerated }
        
        // Đảm bảo đúng thứ tự thời gian (images(for:) thường đã đúng thứ tự nhưng để chắc chắn).
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
    
    /// Trích toàn bộ frame với callback progress (0.0 -> 1.0).
    func extractWithProgress(
        videoUrl: URL,
        at interval: TimeInterval,
        progress: @escaping (Float) -> Void
    ) async throws -> [UIImage] {
        let asset = AVURLAsset(url: videoUrl)
        
        let durationCMTime = try await asset.load(.duration)
        let duration = durationCMTime.seconds
        guard duration.isFinite, duration > 0 else {
            throw VideoExtractorError.cannotReadDuration
        }
        
        var times: [CMTime] = []
        var t: TimeInterval = 0
        while t < duration {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += interval
        }
        guard !times.isEmpty else { throw VideoExtractorError.noFramesGenerated }
        
        let generator = makeHighQualityGenerator(for: asset)
        let total = times.count
        var completedCount = 0
        var results: [(TimeInterval, UIImage)] = []
        
        if #available(iOS 16.0, *) {
            for await result in generator.images(for: times) {
                switch result {
                case .success(requestedTime: let requested, image: let cgImage, actualTime: _):
                    results.append((requested.seconds, makeUIImage(from: cgImage)))
                case .failure(requestedTime: _, error: let error):
                    print("⚠️ Failed to generate frame: \(error.localizedDescription)")
                }
                completedCount += 1
                progress(Float(completedCount) / Float(total))
            }
        } else {
            for time in times {
                do {
                    let cgImage = try await copyCGImage(generator: generator, at: time)
                    results.append((time.seconds, makeUIImage(from: cgImage)))
                } catch {
                    print("⚠️ Failed to generate frame at \(time.seconds)s: \(error.localizedDescription)")
                }
                completedCount += 1
                progress(Float(completedCount) / Float(total))
            }
        }
        
        guard !results.isEmpty else { throw VideoExtractorError.noFramesGenerated }
        
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
    
    /// Trích 1 frame duy nhất tại thời điểm cụ thể — hữu ích khi muốn "chụp" đúng 1 khoảnh khắc chất lượng cao.
    func extractSingleFrame(videoUrl: URL, at time: TimeInterval) async throws -> UIImage {
        let asset = AVURLAsset(url: videoUrl)
        let generator = makeHighQualityGenerator(for: asset)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let cgImage = try await copyCGImage(generator: generator, at: cmTime)
        return makeUIImage(from: cgImage)
    }
    
    // MARK: - iOS < 16 fallback helper
    
    private func copyCGImage(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                switch result {
                case .succeeded:
                    if let cgImage = cgImage {
                        continuation.resume(returning: cgImage)
                    } else {
                        continuation.resume(throwing: VideoExtractorError.generationFailed("No image returned"))
                    }
                case .failed:
                    continuation.resume(throwing: error ?? VideoExtractorError.generationFailed("Unknown error"))
                case .cancelled:
                    continuation.resume(throwing: VideoExtractorError.generationFailed("Cancelled"))
                @unknown default:
                    continuation.resume(throwing: VideoExtractorError.generationFailed("Unknown result"))
                }
            }
        }
    }
}
