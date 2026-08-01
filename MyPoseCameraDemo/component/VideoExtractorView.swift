//
//  VideoExtractorView.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI
import AVKit

struct VideoExtractorView: View {
    @StateObject private var viewModel = VideoExtractorViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        importSection
                        
                        if viewModel.videoURL != nil {
                            videoPreviewSection
                            videoInfoSection
                            extractSection
                        }
                        
                        if viewModel.isExtracting {
                            extractingView
                        }
                        
                        if !viewModel.extractedImages.isEmpty {
                            previewSliderSection
                            saveSection
                        }
                    }
                    .padding()
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Video Frame Extractor")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Đã có lỗi", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .overlay(alignment: .top) {
                if viewModel.showSavedToast {
                    ToastView(icon: "checkmark.circle.fill", text: "Đã lưu vào thư viện ảnh")
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.showSavedToast)
        }
    }
    
    // MARK: - 1. Import
    
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("film.stack", "Nguồn video")
            
            PhotosPicker(
                selection: $viewModel.selectedVideo,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.videoURL == nil ? "square.and.arrow.down" : "arrow.triangle.2.circlepath")
                    Text(viewModel.videoURL == nil ? "Import Video" : "Change Video")
                }
            }
            .buttonStyle(.primary(.blue, disabled: viewModel.isLoadingVideo || viewModel.isExtracting))
            .disabled(viewModel.isLoadingVideo || viewModel.isExtracting)
            
            if viewModel.isLoadingVideo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang tải video...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }
    
    // MARK: - 2. Video Preview
    
    private var videoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("play.rectangle.fill", "Preview")
            
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            
            if let videoURL = viewModel.videoURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(videoURL.path)
                        .font(.caption2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
    
    // MARK: - Video Info Analysis
    
    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("info.circle.fill", "Thông tin video", tint: .indigo)
            
            if viewModel.isAnalyzingVideoInfo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang phân tích video...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let report = viewModel.videoInfoReport {
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
    
    // MARK: - 3. Extract
    
    private var extractSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("wand.and.stars", "Extract")
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Khoảng thời gian mỗi frame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.1fs", viewModel.extractInterval))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
                
                Slider(value: $viewModel.extractInterval, in: 0.1...5.0, step: 0.1)
                    .tint(.green)
                
                HStack {
                    Text("0.1s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("5.0s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Button {
                Task { await viewModel.extractVideo() }
            } label: {
                Label("Extract Video", systemImage: "scissors")
            }
            .buttonStyle(.primary(.green, disabled: viewModel.isExtracting))
            .disabled(viewModel.isExtracting)
        }
        .cardStyle()
    }
    
    private var extractingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.4)
            
            Text("Đang extract video...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            if let progress = viewModel.extractionProgress {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
    
    // MARK: - 4. Preview + Slider
    
    private var previewSliderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader("square.stack.3d.up.fill", "Frames đã extract")
                Spacer()
                PillBadge(text: "\(viewModel.extractedImages.count) frames", color: .blue)
            }
            
            if let image = viewModel.currentImage {
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
                    Text("Frame \(viewModel.currentIndex + 1)/\(viewModel.extractedImages.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.sliderPercentage * 100))% • \(viewModel.currentTimeLabel)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                
                Slider(value: $viewModel.sliderPercentage, in: 0...1)
                    .tint(.blue)
            }
        }
        .cardStyle()
    }
    
    // MARK: - 5. Save
    
    private var saveSection: some View {
        Button {
            Task { await viewModel.saveCurrentFrameToPhotos() }
        } label: {
            if viewModel.isSaving {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Đang lưu...")
                }
            } else {
                Label("Save Frame to Photos", systemImage: "square.and.arrow.down.on.square")
            }
        }
        .buttonStyle(.primary(.blue, disabled: viewModel.isSaving || viewModel.currentImage == nil))
        .disabled(viewModel.isSaving || viewModel.currentImage == nil)
    }
}

#Preview {
    VideoExtractorView()
}
