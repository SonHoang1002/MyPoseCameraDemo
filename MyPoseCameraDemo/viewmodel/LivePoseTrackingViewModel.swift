//
//  LivePoseTrackingViewModel.swift
//  MtPoseCameraDemo26
//
//  Camera session chạy VNDetectHumanBodyPoseRequest + VNDetectFaceLandmarksRequest
//  trên MỖI frame video (real-time) để vẽ skeleton/face landmark đè lên preview,
//  đồng thời đánh giá chất lượng frame (mờ/nét, vị trí có bị cắt mép) và so sánh
//  % tương thích (object + pose) với ảnh mẫu — có tính đến việc tỉ lệ khung hình
//  thực tế (camera zoom, orientation...) có thể khác hoàn toàn với ảnh mẫu.
//

internal import AVFoundation
import Vision
import UIKit
internal import Combine

@MainActor
final class LivePoseTrackingViewModel: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    
    @Published var bodyJoints: [BodyJointPoint] = []
    @Published var faceLandmarkGroups: [FaceLandmarkGroup] = []
    @Published var showLowConfidencePoints = true
    @Published var currentFPS: Double = 0
    
    /// Kích thước PIXEL THỰC của frame hiện tại — camera có thể đổi tỉ lệ (zoom, xoay máy...),
    /// nên phải đọc lại từ chính pixel buffer mỗi lần, KHÔNG giả định cố định.
    @Published var currentFrameSize: CGSize = .zero
    @Published var currentFrameQuality: FrameReliabilityReport?
    
    @Published var liveObjectSimilarityPercent: Double?
    @Published var livePoseSimilarityPercent: Double?
    
    @Published var showError = false
    @Published var errorMessage: String?
    
    /// Ảnh mẫu dùng chung — gán từ bên ngoài qua attach(referenceStore:)
    private var referenceStore: ReferenceImageStore?
    
    /// Feature print + blur detection tốn tài nguyên hơn nhiều so với pose/face request,
    /// nên chỉ tính định kỳ mỗi N frame thay vì mỗi frame.
    private nonisolated(unsafe) var frameCounter = 0
    private let heavyAnalysisFrameInterval = 6
    
    let session = AVCaptureSession()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "live.pose.session.queue")
    private let visionQueue = DispatchQueue(label: "live.pose.vision.queue", qos: .userInitiated)
    private let sequenceHandler = VNSequenceRequestHandler()
    private var isConfigured = false
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    
    func attach(referenceStore: ReferenceImageStore) {
        self.referenceStore = referenceStore
    }
    
    // MARK: - Permission + session lifecycle
    
    func requestPermissionAndStart() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            showError(message: "Chưa được cấp quyền Camera. Vui lòng bật trong Cài đặt > Quyền riêng tư > Camera.")
            return
        }
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
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.showError(message: "Không thể khởi tạo camera trên thiết bị này.")
                }
                return
            }
            self.session.addInput(input)
            
            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
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
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LivePoseTrackingViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Đọc kích thước THỰC của frame ngay tại thời điểm này — không giả định cố định,
        // vì người dùng có thể zoom, xoay máy, hoặc thiết bị đổi định dạng camera bất kỳ lúc nào.
        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        let frameSize = CGSize(width: frameWidth, height: frameHeight)
        
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let faceRequest = VNDetectFaceLandmarksRequest()
        
        do {
            // VNSequenceRequestHandler tối ưu cho việc chạy liên tục trên chuỗi frame video.
            try sequenceHandler.perform([bodyRequest, faceRequest], on: pixelBuffer, orientation: .up)
        } catch {
            return
        }
        
        var joints: [BodyJointPoint] = []
        if let obs = bodyRequest.results?.first, let points = try? obs.recognizedPoints(.all) {
            joints = points.map { key, point in
                BodyJointPoint(jointName: key, displayName: "\(key.rawValue)", location: point.location, confidence: point.confidence)
            }
        }
        
        var faceGroups: [FaceLandmarkGroup] = []
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
                ("faceContour", landmarks.faceContour),
                ("leftEye", landmarks.leftEye),
                ("rightEye", landmarks.rightEye),
                ("nose", landmarks.nose),
                ("outerLips", landmarks.outerLips),
                ("innerLips", landmarks.innerLips)
            ]
            
            faceGroups = regionList.compactMap { name, region in
                let points = convert(region)
                guard !points.isEmpty else { return nil }
                return FaceLandmarkGroup(name: name, points: points)
            }
        }
        
        // Feature print + blur detection tốn tài nguyên hơn nhiều → chỉ tính định kỳ mỗi N frame.
        frameCounter += 1
        var frameFeaturePrint: VNFeaturePrintObservation?
        var blur: BlurAnalysis?
        if frameCounter % heavyAnalysisFrameInterval == 0 {
            frameFeaturePrint = SimilarityHelper.generateFeaturePrint(pixelBuffer: pixelBuffer, orientation: .up)
            blur = FrameQualityAnalyzer.analyzeBlur(pixelBuffer: pixelBuffer)
        }
        
        Task { @MainActor in
            self.bodyJoints = joints
            self.faceLandmarkGroups = faceGroups
            self.currentFrameSize = frameSize
            
            let now = CFAbsoluteTimeGetCurrent()
            let delta = now - self.lastFrameTime
            if delta > 0 {
                self.currentFPS = 1.0 / delta
            }
            self.lastFrameTime = now
            
            // Chỉ cập nhật report chất lượng khi có blur mới tính (giữ report cũ giữa các frame còn lại
            // để UI không bị "giật" giá trị liên tục).
            if let blur {
                self.currentFrameQuality = FrameQualityAnalyzer.buildReliabilityReport(
                    imageSize: frameSize,
                    joints: joints,
                    blur: blur
                )
            }
            
            // So sánh với ảnh mẫu (nếu có) — thực hiện ở đây vì referenceStore là @MainActor.
            if let frameFeaturePrint, let refFP = self.referenceStore?.featurePrint {
                self.liveObjectSimilarityPercent = SimilarityHelper.featurePrintSimilarityPercent(refFP, frameFeaturePrint)
            }
            
            if let refJoints = self.referenceStore?.poseResult?.bodyJoints2D, !refJoints.isEmpty,
               let refSize = self.referenceStore?.imageSize, refSize != .zero, frameSize != .zero {
                self.livePoseSimilarityPercent = SimilarityHelper.poseSimilarityPercent(
                    refJoints, frameSizeA: refSize,
                    joints, frameSizeB: frameSize
                )
            } else {
                self.livePoseSimilarityPercent = nil
            }
        }
    }
}
