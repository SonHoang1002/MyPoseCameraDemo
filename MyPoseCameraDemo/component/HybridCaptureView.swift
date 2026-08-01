//
//  HybridCaptureView.swift
//  MtPoseCameraDemo26
//
//  Demo tab: quay video + chụp burst photo đồng thời trên cùng 1 session.
//  Sau khi dừng quay: hiển thị preview video + slider ảnh burst bên dưới,
//  đồng thời phân tích cả video lẫn ảnh giống 2 tab kia.
//

import SwiftUI
import AVKit

struct HybridCaptureView: View {
    @StateObject private var viewModel = CameraCaptureViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        cameraSection
                        
                        if viewModel.isAnalyzingVideo {
                            analyzingBanner(text: "Đang phân tích video vừa quay...")
                        }
                        
                        if viewModel.recordedVideoURL != nil {
                            recordedVideoSection
                            videoInfoSection
                        }
                        
                        if !viewModel.burstImages.isEmpty {
                            burstPreviewSection
                            analyzeImageButtonSection
                        }
                        
                        if let report = viewModel.selectedBurstReport {
                            burstImageAnalysisSection(report)
                        }
                    }
                    .padding()
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Hybrid Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.hasResults {
                        Button {
                            withAnimation { viewModel.reset() }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .task {
                await viewModel.requestPermissionsAndStart()
            }
            .onDisappear {
                viewModel.stopSession()
            }
            .alert("Đã có lỗi", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
    
    // MARK: - Camera live preview + controls
    
    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("camera.fill", "Camera", tint: .red)
            
            ZStack(alignment: .bottom) {
                if viewModel.isSessionRunning {
                    CameraPreviewView(session: viewModel.session)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    EmptyStatePlaceholder(icon: "camera.viewfinder", text: "Đang khởi tạo camera...", height: 320)
                }
                
                if viewModel.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("REC")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if viewModel.isCapturingBurst {
                    PillBadge(text: "Burst \(viewModel.burstCount - viewModel.burstShotsRemaining + 1)/\(viewModel.burstCount)", color: .orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            
            controlsRow
            
            burstCountStepper
        }
        .cardStyle()
    }
    
    private var controlsRow: some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.fill" : "video.fill")
            }
            .buttonStyle(.primary(viewModel.isRecording ? .gray : .red, disabled: !viewModel.isSessionRunning))
            .disabled(!viewModel.isSessionRunning)
            
            Button {
                viewModel.captureBurst()
            } label: {
                Label("Burst", systemImage: "camera.aperture")
            }
            .buttonStyle(.primary(.orange, disabled: !viewModel.isSessionRunning || viewModel.isCapturingBurst))
            .disabled(!viewModel.isSessionRunning || viewModel.isCapturingBurst)
        }
    }
    
    private var burstCountStepper: some View {
        HStack {
            Text("Số ảnh mỗi lần burst")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Stepper("\(viewModel.burstCount) ảnh", value: $viewModel.burstCount, in: 2...15)
                .fixedSize()
                .font(.caption.weight(.semibold))
        }
    }
    
    // MARK: - Recorded video preview
    
    private var recordedVideoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("play.rectangle.fill", "Video vừa quay")
            
            if let url = viewModel.recordedVideoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.caption2)
                    Text(url.path)
                        .font(.caption2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
    
    // MARK: - Video info analysis (dùng lại VideoInfoReport)
    
    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("info.circle.fill", "Thông tin video", tint: .indigo)
            
            if let report = viewModel.videoInfoReport {
                infoGroup(title: "File & Container", icon: "doc.fill", lines: report.fileSummaryLines)
                infoGroup(title: "Video Track", icon: "video.fill", lines: report.videoSummaryLines)
                infoGroup(title: "Audio Track", icon: "waveform", lines: report.audioSummaryLines)
            }
        }
        .cardStyle()
    }
    
    private func infoGroup(title: String, icon: String, lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.indigo)
                .padding(.bottom, 2)
            
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    MetadataRow(label: line.0, value: line.1)
                    if index != lines.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.indigo.opacity(0.06))
            )
        }
    }
    
    // MARK: - Burst photos preview + slider
    
    private var burstPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader("square.stack.3d.up.fill", "Ảnh burst")
                Spacer()
                PillBadge(text: "\(viewModel.burstImages.count) ảnh", color: .orange)
            }
            
            if let image = viewModel.currentBurstImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Ảnh \(viewModel.currentBurstIndex + 1)/\(viewModel.burstImages.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.sliderPercentage * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                
                Slider(value: $viewModel.sliderPercentage, in: 0...1)
                    .tint(.orange)
                    .onChange(of: viewModel.sliderPercentage) { _, _ in
                        viewModel.selectedBurstReport = nil
                    }
            }
        }
        .cardStyle()
    }
    
    private var analyzeImageButtonSection: some View {
        Button {
            viewModel.analyzeSelectedBurstImage()
        } label: {
            Label("Analyze Ảnh Đang Chọn", systemImage: "waveform.and.magnifyingglass")
        }
        .buttonStyle(.primary(.purple, disabled: viewModel.currentBurstImage == nil))
        .disabled(viewModel.currentBurstImage == nil)
    }
    
    // MARK: - Burst image analysis result (dùng lại ImageQualityReport)
    
    private func burstImageAnalysisSection(_ report: ImageQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("chart.bar.doc.horizontal", "Phân tích ảnh burst", tint: .purple)
            
            VStack(spacing: 0) {
                ForEach(Array(report.summaryLines.enumerated()), id: \.offset) { index, line in
                    MetadataRow(label: line.0, value: line.1)
                    if index != report.summaryLines.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.purple.opacity(0.06))
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("So với ảnh chụp camera thường:")
                        .font(.caption.weight(.bold))
                    Text(report.cameraEquivalenceVerdict)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.purple)
                }
                Text(report.cameraEquivalenceDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
    
    private func analyzingBanner(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

#Preview {
    HybridCaptureView()
}
