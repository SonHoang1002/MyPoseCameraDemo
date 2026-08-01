 
//
//  CameraCaptureViewModel.swift
//  MtPoseCameraDemo26
//
//  Quản lý AVCaptureSession để vừa quay video (AVCaptureMovieFileOutput)
//  vừa chụp ảnh burst (AVCapturePhotoOutput) trên CÙNG một session —
//  đây là kiểu "hybrid capture" giống chế độ chụp ảnh trong lúc quay video.
//
//  Lưu ý kỹ thuật: khi dùng chung session, độ phân giải ảnh chụp sẽ bị giới hạn
//  bởi sessionPreset đang dùng cho video (ở đây là .high), nên ảnh burst sẽ
//  KHÔNG đạt full resolution như chụp ảnh thường (chế độ .photo riêng biệt).
//  Đây là đánh đổi cố hữu của hybrid capture trên non-multi-cam device.
//

@preconcurrency internal import AVFoundation
import UIKit
internal import Combine

@MainActor
final class CameraCaptureViewModel: NSObject, ObservableObject {
    // MARK: - Session state
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var isCapturingBurst = false
    @Published var burstShotsRemaining = 0
    @Published var burstCount: Int = 5
    
    // MARK: - Results
    @Published var burstImages: [UIImage] = []
    @Published var recordedVideoURL: URL?
    @Published var sliderPercentage: Float = 0
    
    // MARK: - Analysis
    @Published var videoInfoReport: VideoInfoReport?
    @Published var isAnalyzingVideo = false
    @Published var selectedBurstReport: ImageQualityReport?
    
    // MARK: - Error
    @Published var showError = false
    @Published var errorMessage: String?
    
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    
    // MARK: - Computed (slider through burst photos)
    
    var currentBurstIndex: Int {
        guard !burstImages.isEmpty else { return 0 }
        let lastIndex = burstImages.count - 1
        let raw = Int((sliderPercentage * Float(lastIndex)).rounded())
        return min(max(raw, 0), lastIndex)
    }
    
    var currentBurstImage: UIImage? {
        guard burstImages.indices.contains(currentBurstIndex) else { return nil }
        return burstImages[currentBurstIndex]
    }
    
    var hasResults: Bool {
        recordedVideoURL != nil || !burstImages.isEmpty
    }
    
    // MARK: - Permissions + Session setup
    
    func requestPermissionsAndStart() async {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard videoGranted else {
            showError(message: "Chưa được cấp quyền Camera. Vui lòng bật trong Cài đặt > Quyền riêng tư > Camera.")
            return
        }
        
        // Mic là optional — nếu từ chối vẫn quay được video (chỉ không có audio).
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        
        configureSessionIfNeeded()
    }
    
    private func configureSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            if self.isConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                    Task { @MainActor in self.isSessionRunning = true }
                }
                return
            }
            
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(videoInput) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.showError(message: "Không thể khởi tạo camera trên thiết bị này.")
                }
                return
            }
            self.session.addInput(videoInput)
            
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
            
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
            self.isConfigured = true
            
            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        isSessionRunning = false
    }
    
    // MARK: - Recording
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Reset kết quả lần trước
        burstImages = []
        recordedVideoURL = nil
        videoInfoReport = nil
        selectedBurstReport = nil
        sliderPercentage = 0
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        }
        isRecording = true
    }
    
    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }
    
    // MARK: - Burst photo capture (chụp nhanh liên tiếp — dùng được cả khi đang quay)
    
    func captureBurst() {
        guard !isCapturingBurst else { return }
        isCapturingBurst = true
        burstShotsRemaining = burstCount
        captureNextBurstPhoto()
    }
    
    private func captureNextBurstPhoto() {
        guard burstShotsRemaining > 0 else {
            isCapturingBurst = false
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - Analyze
    
    func analyzeVideo() async {
        guard let url = recordedVideoURL else { return }
        isAnalyzingVideo = true
        do {
            let report = try await VideoInfoAnalyzer.analyze(url: url)
            self.videoInfoReport = report
        } catch {
            showError(message: "Phân tích video thất bại: \(error.localizedDescription)")
        }
        isAnalyzingVideo = false
    }
    
    func analyzeSelectedBurstImage() {
        guard let image = currentBurstImage else { return }
        selectedBurstReport = ImageQualityAnalyzer.analyze(image)
    }
    
    func reset() {
        burstImages = []
        recordedVideoURL = nil
        videoInfoReport = nil
        selectedBurstReport = nil
        sliderPercentage = 0
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraCaptureViewModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            
            if let error {
                self.showError(message: "Ghi video thất bại: \(error.localizedDescription)")
                return
            }
            
            self.recordedVideoURL = outputFileURL
            await self.analyzeVideo()
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraCaptureViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer {
                self.burstShotsRemaining -= 1
                if self.burstShotsRemaining > 0 {
                    self.captureNextBurstPhoto()
                } else {
                    self.isCapturingBurst = false
                }
            }
            
            if let error {
                self.showError(message: "Chụp ảnh thất bại: \(error.localizedDescription)")
                return
            }
            
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else { return }
            
            self.burstImages.append(image)
            self.sliderPercentage = 0
        }
    }
}
