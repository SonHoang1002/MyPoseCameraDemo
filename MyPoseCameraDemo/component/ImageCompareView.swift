//
//  ImageCompareView.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI

struct ImageCompareView: View {
    @StateObject private var viewModel = ImageCompareViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        importRow
                        
                        if viewModel.image1 != nil || viewModel.image2 != nil {
                            previewRow
                        }
                        
                        if let report1 = viewModel.report1, let report2 = viewModel.report2 {
                            metadataComparisonSection(report1: report1, report2: report2)
                            
                            if let comparison = viewModel.comparison {
                                verdictSection(comparison)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Compare Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.image1 != nil || viewModel.image2 != nil {
                        Button {
                            withAnimation { viewModel.reset() }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .alert("Đã có lỗi", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
    
    // MARK: - Import 2 ảnh
    
    private var importRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("square.on.square", "Import 2 ảnh để so sánh")
            
            HStack(spacing: 12) {
                importButton(
                    title: "Ảnh 1",
                    selection: $viewModel.selectedItem1,
                    isLoading: viewModel.isLoading1,
                    hasImage: viewModel.image1 != nil,
                    color: .blue
                )
                
                importButton(
                    title: "Ảnh 2",
                    selection: $viewModel.selectedItem2,
                    isLoading: viewModel.isLoading2,
                    hasImage: viewModel.image2 != nil,
                    color: .green
                )
            }
        }
        .cardStyle()
    }
    
    private func importButton(title: String, selection: Binding<PhotosPickerItem?>, isLoading: Bool, hasImage: Bool, color: Color) -> some View {
        PhotosPicker(selection: selection, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: hasImage ? "checkmark.circle.fill" : "photo.badge.plus")
                        .font(.system(size: 22))
                }
                Text(hasImage ? "\(title) ✓" : "Import \(title)")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
        }
        .disabled(isLoading)
    }
    
    // MARK: - Preview 2 ảnh
    
    private var previewRow: some View {
        HStack(alignment: .top, spacing: 12) {
            imagePreviewCard(title: "Ảnh 1", image: viewModel.image1, color: .blue)
            imagePreviewCard(title: "Ảnh 2", image: viewModel.image2, color: .green)
        }
        .cardStyle()
    }
    
    private func imagePreviewCard(title: String, image: UIImage?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PillBadge(text: title, color: color)
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(color.opacity(0.35), lineWidth: 2)
                    )
            } else {
                EmptyStatePlaceholder(icon: "photo", text: "Chưa có ảnh", height: 160)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bảng metadata song song
    
    private func metadataComparisonSection(report1: ImageQualityReport, report2: ImageQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("chart.bar.doc.horizontal", "So sánh metadata")
            
            VStack(spacing: 0) {
                comparisonHeaderRow
                Divider().padding(.horizontal, 10)
                
                ForEach(Array(zippedRows(report1, report2).enumerated()), id: \.offset) { index, row in
                    comparisonRow(label: row.0, value1: row.1, value2: row.2)
                    if index != zippedRows(report1, report2).count - 1 {
                        Divider().padding(.horizontal, 10)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .cardStyle()
    }
    
    private var comparisonHeaderRow: some View {
        HStack {
            Text("Thông số")
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Ảnh 1")
                .font(.caption.weight(.bold))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Ảnh 2")
                .font(.caption.weight(.bold))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
    
    private func comparisonRow(label: String, value1: String, value2: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value1)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(value2)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    
    private func zippedRows(_ r1: ImageQualityReport, _ r2: ImageQualityReport) -> [(String, String, String)] {
        let lines1 = r1.summaryLines
        let lines2 = r2.summaryLines
        let labels = Set(lines1.map { $0.0 }).union(lines2.map { $0.0 })
        let orderedLabels = lines1.map { $0.0 } + labels.subtracting(lines1.map { $0.0 })
        
        return orderedLabels.map { label in
            let v1 = lines1.first(where: { $0.0 == label })?.1 ?? "-"
            let v2 = lines2.first(where: { $0.0 == label })?.1 ?? "-"
            return (label, v1, v2)
        }
    }
    
    // MARK: - Nhận định tổng quan
    
    private func verdictSection(_ comparison: ImageComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("sparkle.magnifyingglass", "Nhận định", tint: .purple)
            
            VStack(alignment: .leading, spacing: 10) {
                verdictLine(icon: "square.resize", text: comparison.resolutionWinner)
                verdictLine(icon: "doc.fill", text: comparison.fileSizeWinner)
                verdictLine(icon: "circle.lefthalf.filled", text: comparison.bitDepthNote)
                verdictLine(icon: "paintpalette", text: comparison.colorSpaceNote)
            }
            
            Divider()
            
            Text(comparison.overallNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.purple.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func verdictLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 18)
            Text(text)
                .font(.caption)
        }
    }
}

#Preview {
    ImageCompareView()
}
