//
//  ContentView.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = VideoExtractorViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Video Preview
                videoPreviewSection
                
                // Extract Options
                extractOptionsSection
                
                // Loading
                if viewModel.isLoading {
                    loadingView
                }
                
                // Results
                if !viewModel.extractedImages.isEmpty {
                    resultsSection
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Video Frame Extractor")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
    
    // MARK: - UI Components
    
    private var headerView: some View {
        VStack(spacing: 10) {
            PhotosPicker(
                selection: $viewModel.selectedVideo,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Choose Video", systemImage: "video.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isLoading)
            
            if let videoName = viewModel.videoName {
                Text("📹 \(videoName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var videoPreviewSection: some View {
        if let player = viewModel.player {
            VideoPlayer(player: player)
                .frame(height: 250)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 250)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No video selected")
                            .foregroundColor(.gray)
                    }
                )
        }
    }
    
    private var extractOptionsSection: some View {
        VStack(spacing: 12) {
            // Interval Picker
            if viewModel.videoURL != nil && !viewModel.isLoading {
                HStack {
                    Text("Interval:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Interval", selection: $viewModel.extractInterval) {
                        Text("0.5s").tag(0.5)
                        Text("1.0s").tag(1.0)
                        Text("2.0s").tag(2.0)
                        Text("5.0s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                
                HStack(spacing: 12) {
                    // Extract All Button (no progress)
                    Button(action: {
                        Task {
                            await viewModel.extractAllFrames()
                        }
                    }) {
                        Label("Extract All", systemImage: "scissors")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .disabled(viewModel.isLoading)
                    
                    // Extract with Progress Button
                    Button(action: {
                        Task {
                            await viewModel.extractWithProgress()
                        }
                    }) {
                        Label("Extract + Progress", systemImage: "chart.bar.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(viewModel.extractionMode == .withProgress ? "Extracting with progress..." : "Extracting all frames...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let progress = viewModel.extractionProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Processing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var resultsSection: some View {
        VStack(spacing: 12) {
            Text("🎬 \(viewModel.extractedImages.count) frames extracted")
                .font(.headline)
            
            // Frame info
            HStack {
                Text("Frame \(Int(viewModel.selectedFrameIndex) + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("/ \(viewModel.extractedImages.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Slider
            Slider(
                value: $viewModel.selectedFrameIndex,
                in: 0...Float(max(0, viewModel.extractedImages.count - 1)),
                step: 1
            )
            .disabled(viewModel.extractedImages.isEmpty)
            .accentColor(.blue)
            
            // Preview image
            if let selectedImage = viewModel.selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.saveSelectedFrame()
                }) {
                    Label("Save Frame", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.saveAllFrames()
                }) {
                    Label("Save All", systemImage: "square.and.arrow.down.fill")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
