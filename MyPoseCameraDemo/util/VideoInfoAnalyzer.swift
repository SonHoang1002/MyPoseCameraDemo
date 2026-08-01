//
//  VideoInfoAnalyzer.swift
//  MtPoseCameraDemo26
//
//  Phân tích toàn bộ metadata kỹ thuật của 1 file video: container, video track
//  (codec, resolution, frame rate, bitrate, color info), audio track, dung lượng file.
//

internal import AVFoundation
import UIKit

struct VideoInfoReport {
    // File / container
    let fileSizeBytes: Int
    let fileExtension: String
    let durationSeconds: Double
    let overallBitrateMbps: Double
    
    // Video track
    let hasVideoTrack: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let displayWidth: Int          // sau khi áp dụng preferredTransform (xoay)
    let displayHeight: Int
    let megapixels: Double
    let aspectRatio: String
    let videoCodec: String
    let frameRate: Double
    let videoBitrateMbps: Double?
    let isHDR: Bool
    let colorPrimaries: String
    let rotationDegrees: Int
    
    // Audio track
    let hasAudioTrack: Bool
    let audioCodec: String?
    let sampleRateHz: Double?
    let channelCount: Int?
    let audioBitrateKbps: Double?
    
    var fileSummaryLines: [(String, String)] {
        [
            ("Dung lượng file", formatBytes(fileSizeBytes)),
            ("Định dạng container", fileExtension.uppercased()),
            ("Thời lượng", formatDuration(durationSeconds)),
            ("Bitrate tổng thể", String(format: "%.2f Mbps", overallBitrateMbps))
        ]
    }
    
    var videoSummaryLines: [(String, String)] {
        guard hasVideoTrack else { return [("Video track", "Không có")] }
        var lines: [(String, String)] = [
            ("Độ phân giải hiển thị", "\(displayWidth) x \(displayHeight) px"),
            ("Độ phân giải gốc (encode)", "\(pixelWidth) x \(pixelHeight) px"),
            ("Độ phân giải", String(format: "%.2f MP", megapixels)),
            ("Tỉ lệ khung hình", aspectRatio),
            ("Codec", videoCodec),
            ("Frame rate", String(format: "%.2f fps", frameRate)),
            ("Góc xoay (rotation)", "\(rotationDegrees)°"),
            ("Color primaries", colorPrimaries),
            ("HDR", isHDR ? "Có" : "Không")
        ]
        if let videoBitrateMbps {
            lines.insert(("Bitrate video", String(format: "%.2f Mbps", videoBitrateMbps)), at: 5)
        }
        return lines
    }
    
    var audioSummaryLines: [(String, String)] {
        guard hasAudioTrack else { return [("Audio track", "Không có")] }
        var lines: [(String, String)] = []
        if let audioCodec { lines.append(("Codec âm thanh", audioCodec)) }
        if let sampleRateHz { lines.append(("Sample rate", String(format: "%.0f Hz", sampleRateHz))) }
        if let channelCount { lines.append(("Số kênh", channelCount == 1 ? "Mono" : channelCount == 2 ? "Stereo" : "\(channelCount) kênh")) }
        if let audioBitrateKbps { lines.append(("Bitrate âm thanh", String(format: "%.0f kbps", audioBitrateKbps))) }
        return lines
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes > 1_000_000 {
            return String(format: "%.2f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - seconds.rounded(.down)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }
}

enum VideoInfoAnalyzer {
    
    enum AnalyzerError: LocalizedError {
        case cannotReadAsset
        var errorDescription: String? { "Không đọc được thông tin video" }
    }
    
    static func analyze(url: URL) async throws -> VideoInfoReport {
        let asset = AVURLAsset(url: url)
        
        async let durationTask = asset.load(.duration)
        async let tracksTask = asset.load(.tracks)
        
        let duration = try await durationTask.seconds
        let tracks = try await tracksTask
        
        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let overallBitrateMbps = duration > 0 ? (Double(fileSizeBytes ?? 0) * 8 / 1_000_000) / duration : 0
        
        let videoTrack = tracks.first(where: { $0.mediaType == .video })
        let audioTrack = tracks.first(where: { $0.mediaType == .audio })
        
        // MARK: Video track info
        var pixelWidth = 0, pixelHeight = 0
        var displayWidth = 0, displayHeight = 0
        var videoCodec = "-"
        var frameRate: Double = 0
        var videoBitrateMbps: Double? = nil
        var isHDR = false
        var colorPrimaries = "-"
        var rotationDegrees = 0
        
        if let videoTrack {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            
            pixelWidth = Int(abs(naturalSize.width))
            pixelHeight = Int(abs(naturalSize.height))
            
            let transformedSize = naturalSize.applying(transform)
            displayWidth = Int(abs(transformedSize.width))
            displayHeight = Int(abs(transformedSize.height))
            
            frameRate = Double(nominalFrameRate)
            videoBitrateMbps = Double(estimatedDataRate) / 1_000_000
            
            let angle = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
            rotationDegrees = Int((angle).rounded())
            if rotationDegrees < 0 { rotationDegrees += 360 }
            
            if let formatDescription = formatDescriptions.first {
                let subType = CMFormatDescriptionGetMediaSubType(formatDescription)
                videoCodec = fourCharCodeToString(subType)
                
                if let colorPrimariesKey = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) {
                    let raw = "\(colorPrimariesKey)"
                    colorPrimaries = raw
                    isHDR = raw.contains("2020")
                } else {
                    colorPrimaries = "Không xác định (giả định Rec.709 / SDR)"
                }
            }
        }
        
        // MARK: Audio track info
        var audioCodec: String? = nil
        var sampleRateHz: Double? = nil
        var channelCount: Int? = nil
        var audioBitrateKbps: Double? = nil
        
        if let audioTrack {
            let estimatedDataRate = try await audioTrack.load(.estimatedDataRate)
            let formatDescriptions = try await audioTrack.load(.formatDescriptions)
            audioBitrateKbps = Double(estimatedDataRate) / 1000
            
            if let formatDescription = formatDescriptions.first {
                let subType = CMFormatDescriptionGetMediaSubType(formatDescription)
                audioCodec = fourCharCodeToString(subType)
                
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                    sampleRateHz = asbd.pointee.mSampleRate
                    channelCount = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
        }
        
        let aspect = aspectRatioString(displayWidth, displayHeight)
        let megapixels = Double(displayWidth * displayHeight) / 1_000_000
        
        return VideoInfoReport(
            fileSizeBytes: fileSizeBytes,
            fileExtension: ext,
            durationSeconds: duration,
            overallBitrateMbps: overallBitrateMbps,
            hasVideoTrack: videoTrack != nil,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            megapixels: megapixels,
            aspectRatio: aspect,
            videoCodec: videoCodec,
            frameRate: frameRate,
            videoBitrateMbps: videoBitrateMbps,
            isHDR: isHDR,
            colorPrimaries: colorPrimaries,
            rotationDegrees: rotationDegrees,
            hasAudioTrack: audioTrack != nil,
            audioCodec: audioCodec,
            sampleRateHz: sampleRateHz,
            channelCount: channelCount,
            audioBitrateKbps: audioBitrateKbps
        )
    }
    
    private static func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let raw = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
        
        // Map các FourCC phổ biến sang tên dễ đọc
        switch raw {
        case "avc1": return "H.264 (AVC)"
        case "hvc1", "hev1": return "H.265 (HEVC)"
        case "mp4a": return "AAC"
        case "aac ": return "AAC"
        default: return raw.isEmpty ? "Không xác định" : raw
        }
    }
    
    private static func aspectRatioString(_ w: Int, _ h: Int) -> String {
        guard w > 0, h > 0 else { return "-" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(w, h)
        guard g > 0 else { return "-" }
        return "\(w / g):\(h / g)"
    }
}
