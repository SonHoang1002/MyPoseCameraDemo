//
//  PoseAnalysisView.swift
//  MtPoseCameraDemo26
//
//  Tab: import 1 ảnh, hiển thị overlay pose 2D + face landmarks, và bảng chi tiết
//  body 3D joints (toạ độ x,y,z theo mét) + face landmarks.
//

import SwiftUI
import PhotosUI

struct PoseAnalysisView: View {
    @StateObject private var viewModel = PoseAnalysisViewModel()
    @ObservedObject var referenceStore: ReferenceImageStore
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        referenceImportSection
                        if referenceStore.hasReference {
                            referenceQualitySection()
                        }
                        importSection
                        
                        if viewModel.isAnalyzing {
                            analyzingBanner
                        }
                        
                        if let image = viewModel.image {
                            imagePreviewSection(image)
                            togglesSection
                            qualitySection(title: "Chất lượng & độ tin cậy ảnh import", report: viewModel.frameQuality, tint: .teal)
                        }
                        
                        if viewModel.hasBody {
                            body2DSection
                        }
                        
                        if viewModel.has3DBody {
                            body3DSection
                        }
                        
                        if viewModel.hasFace {
                            faceSection
                        }
                        
                        if let image = viewModel.image, !viewModel.isAnalyzing,
                           !viewModel.hasBody && !viewModel.hasFace {
                            noDetectionBanner
                        }
                        
                        if referenceStore.hasReference && viewModel.image != nil {
                            comparisonSection
                            
                            if let detailedGroups = detailedComparison {
                                detailedJointSection(detailedGroups)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Pose Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.image != nil {
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
    
    // MARK: - Import
    
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("figure.walk", "Import ảnh để phân tích pose")
            
            PhotosPicker(selection: $viewModel.selectedItem, matching: .images, photoLibrary: .shared()) {
                Label(viewModel.image == nil ? "Import Ảnh" : "Chọn ảnh khác", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.primary(.teal))
        }
        .cardStyle()
    }
    
    private var analyzingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Đang phân tích pose & face landmarks...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
    
    private var noDetectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Không phát hiện được người hoặc khuôn mặt trong ảnh này.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
    
    // MARK: - Image preview + overlay
    
    private func imagePreviewSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("viewfinder", "Preview + Overlay")
            
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                
                PoseOverlayCanvas(
                    joints: viewModel.bodyJoints2D,
                    faceLandmarkGroups: viewModel.faceLandmarkGroups,
                    showLowConfidencePoints: viewModel.showLowConfidencePoints
                )
            }
            .aspectRatio(image.size, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            legendRow
        }
        .cardStyle()
    }
    
    private var legendRow: some View {
        HStack(spacing: 14) {
            legendDot(color: .green, text: "Rõ ràng")
            legendDot(color: .orange, text: "Không chắc chắn")
            legendDot(color: .red, text: "Có thể bị khuất")
            legendDot(color: .cyan, text: "Face")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    
    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
    
    private var togglesSection: some View {
        Toggle(isOn: $viewModel.showLowConfidencePoints) {
            Label("Hiện cả điểm bị khuất / độ tin cậy thấp", systemImage: "eye.trianglebadge.exclamationmark")
                .font(.caption)
        }
        .cardStyle()
    }
    
    // MARK: - Body 2D table
    
    private var body2DSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("figure.stand", "Body Pose (2D)")
                Spacer()
                PillBadge(text: "\(viewModel.bodyJoints2D.count) điểm", color: .green)
            }
            
            VStack(spacing: 0) {
                ForEach(viewModel.bodyJoints2D.sorted(by: { $0.displayName < $1.displayName })) { joint in
                    MetadataRow(
                        label: joint.displayName,
                        value: String(format: "%.0f%%", joint.confidence * 100),
                        valueColor: confidenceColor(joint.confidence)
                    )
                    Divider()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.06)))
        }
        .cardStyle()
    }
    
    // MARK: - Body 3D table
    
    private var body3DSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("cube.transparent", "Body Pose (3D)", tint: .blue)
                Spacer()
                PillBadge(text: "\(viewModel.body3DJoints.count) điểm", color: .blue)
            }
            
            Text("Toạ độ (x, y, z) tính bằng mét, tương đối so với khớp gốc (root/hip).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 0) {
                ForEach(viewModel.body3DJoints.sorted(by: { $0.displayName < $1.displayName })) { joint in
                    MetadataRow(label: joint.displayName, value: joint.summaryValue)
                    Divider()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.opacity(0.06)))
        }
        .cardStyle()
    }
    
    // MARK: - Face landmarks table
    
    private var faceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("face.smiling", "Face Landmarks chi tiết", tint: .purple)
                Spacer()
                let totalPoints = viewModel.faceLandmarkGroups.reduce(0) { $0 + $1.count }
                PillBadge(text: "\(totalPoints) điểm", color: .purple)
            }
            
            VStack(spacing: 0) {
                ForEach(viewModel.faceLandmarkGroups) { group in
                    MetadataRow(label: group.name, value: "\(group.count) điểm")
                    Divider()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.purple.opacity(0.06)))
        }
        .cardStyle()
    }
    
    // MARK: - Reference (ảnh mẫu) — DÙNG CHUNG với tab Live Pose
    
    private var referenceImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("photo.on.rectangle.angled", "Ảnh mẫu (dùng chung)", tint: .orange)
                Spacer()
                if referenceStore.hasReference {
                    Button {
                        withAnimation { referenceStore.reset() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack(spacing: 12) {
                if let refImage = referenceStore.image {
                    Image(uiImage: refImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "photo").foregroundStyle(.orange.opacity(0.5)))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $referenceStore.selectedItem, matching: .images, photoLibrary: .shared()) {
                        Label(referenceStore.hasReference ? "Đổi ảnh mẫu" : "Import ảnh mẫu", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.primary(.orange))
                    
                    if referenceStore.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Đang phân tích ảnh mẫu...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if referenceStore.hasReference {
                        Text(referenceStore.hasReferencePose ? "Đã phát hiện pose trong ảnh mẫu" : "Không phát hiện pose trong ảnh mẫu")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
        .alert("Đã có lỗi", isPresented: $referenceStore.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(referenceStore.errorMessage ?? "Unknown error")
        }
    }
    
    private func referenceQualitySection() -> some View {
        qualitySection(title: "Chất lượng & độ tin cậy ảnh mẫu", report: referenceStore.frameQuality, tint: .orange)
    }
    
    // MARK: - So sánh với ảnh mẫu
    
    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("percent", "Độ tương thích với ảnh mẫu", tint: .pink)
            
            if let lowReliabilityWarning = lowReliabilityWarning() {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(lowReliabilityWarning)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.08)))
            }
            
            if let refFP = referenceStore.featurePrint, let curFP = viewModel.featurePrint,
               let visualPercent = SimilarityHelper.featurePrintSimilarityPercent(refFP, curFP) {
                similarityRow(
                    title: "Tương đồng hình ảnh / object tổng thể",
                    percent: visualPercent,
                    icon: "photo.stack"
                )
            }
            
            if let refJoints = referenceStore.poseResult?.bodyJoints2D, !refJoints.isEmpty,
               referenceStore.imageSize != .zero, viewModel.imageSize != .zero,
               let posePercent = SimilarityHelper.poseSimilarityPercent(
                   refJoints, frameSizeA: referenceStore.imageSize,
                   viewModel.bodyJoints2D, frameSizeB: viewModel.imageSize
               ) {
                similarityRow(
                    title: "Khớp tư thế (pose)",
                    percent: posePercent,
                    icon: "figure.stand"
                )
            } else if referenceStore.hasReferencePose && viewModel.hasBody {
                Text("Không đủ điểm khớp chung đáng tin cậy giữa 2 ảnh để so tư thế.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if let refAspect = referenceStore.frameQuality?.aspectRatioString,
               let curAspect = viewModel.frameQuality?.aspectRatioString, refAspect != curAspect {
                HStack(spacing: 6) {
                    Image(systemName: "aspectratio").font(.caption2)
                    Text("Tỉ lệ khung hình khác nhau: ảnh mẫu \(refAspect) vs ảnh hiện tại \(curAspect) — đã tự động quy đổi theo pixel thực khi so pose, không bị méo.")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
            
            Text("Lưu ý: đây là ước lượng heuristic dựa trên khoảng cách feature-print và sai khác vị trí khớp — không phải phép đo tương đồng được Apple xác nhận chính xác tuyệt đối.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.pink.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.pink.opacity(0.15), lineWidth: 1))
    }
    
    private func similarityRow(title: String, percent: Double, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(percentColor(percent))
            }
            
            ProgressView(value: percent, total: 100)
                .tint(percentColor(percent))
        }
    }
    
    private func percentColor(_ percent: Double) -> Color {
        if percent >= 70 { return .green }
        if percent >= 40 { return .orange }
        return .red
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.5 { return .green }
        if confidence > 0.3 { return .orange }
        return .red
    }
    
    // MARK: - Quality / reliability report (dùng chung cho ảnh mẫu & ảnh import)
    
    private func qualitySection(title: String, report: FrameReliabilityReport?, tint: Color) -> some View {
        Group {
            if let report {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader("checkmark.shield", title, tint: tint)
                        Spacer()
                        PillBadge(text: report.verdict, color: reliabilityColor(report.overallReliabilityPercent))
                    }
                    
                    HStack {
                        Text("Độ tin cậy tổng hợp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", report.overallReliabilityPercent))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(reliabilityColor(report.overallReliabilityPercent))
                    }
                    ProgressView(value: report.overallReliabilityPercent, total: 100)
                        .tint(reliabilityColor(report.overallReliabilityPercent))
                    
                    HStack(spacing: 16) {
                        if let blur = report.blur {
                            Label(blur.isLikelyBlurry ? "Có thể bị mờ" : "Đủ nét", systemImage: blur.isLikelyBlurry ? "camera.metering.unknown" : "checkmark.seal")
                                .font(.caption2)
                                .foregroundStyle(blur.isLikelyBlurry ? .red : .green)
                        }
                        Label("\(report.visibleJointCount)/\(report.totalJointCount) khớp rõ ràng", systemImage: "figure.stand")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Label("Tỉ lệ \(report.aspectRatioString)", systemImage: "aspectratio")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(report.warningMessages, id: \.self) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
    
    private func reliabilityColor(_ percent: Double) -> Color {
        if percent >= 75 { return .green }
        if percent >= 45 { return .orange }
        return .red
    }
    
    private func lowReliabilityWarning() -> String? {
        let refPercent = referenceStore.frameQuality?.overallReliabilityPercent ?? 100
        let curPercent = viewModel.frameQuality?.overallReliabilityPercent ?? 100
        
        if refPercent < 45 && curPercent < 45 {
            return "Cả ảnh mẫu và ảnh import đều có độ tin cậy thấp — % so sánh bên dưới chỉ mang tính tham khảo."
        } else if refPercent < 45 {
            return "Ảnh mẫu có độ tin cậy thấp (mờ hoặc bị cắt mép) — % so sánh bên dưới có thể không chính xác."
        } else if curPercent < 45 {
            return "Ảnh import có độ tin cậy thấp (mờ hoặc bị cắt mép) — % so sánh bên dưới có thể không chính xác."
        }
        return nil
    }
    
    // MARK: - Phân tích chi tiết từng điểm (theo nhóm bộ phận cơ thể)
    
    private var detailedComparison: [BodyPartGroupComparison]? {
        guard viewModel.imageSize != .zero, referenceStore.imageSize != .zero else { return nil }
        return SimilarityHelper.detailedJointComparison(
            currentJoints: viewModel.bodyJoints2D,
            currentFrameSize: viewModel.imageSize,
            referenceJoints: referenceStore.poseResult?.bodyJoints2D ?? [],
            referenceFrameSize: referenceStore.imageSize
        )
    }
    
    private func detailedJointSection(_ groups: [BodyPartGroupComparison]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("list.bullet.rectangle", "Phân tích chi tiết từng điểm", tint: .indigo)
            
            Text("% lệch so với ảnh mẫu tính riêng cho từng khớp, kèm kiểm tra vị trí trong khung hình hiện tại (có bị sát mép / độ tin cậy thấp hay không).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            ForEach(groups) { group in
                bodyPartGroupCard(group)
            }
        }
        .cardStyle()
    }
    
    private func bodyPartGroupCard(_ group: BodyPartGroupComparison) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(group.joints) { joint in
                    jointDetailRow(joint)
                    if joint.id != group.joints.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label(group.groupName, systemImage: group.icon)
                    .font(.caption.weight(.semibold))
                
                if group.hasAnyPositionWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                if let avg = group.averageMatchPercent {
                    Text(String(format: "%.0f%%", avg))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(percentColor(avg))
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.indigo.opacity(0.06)))
    }
    
    private func jointDetailRow(_ joint: JointComparisonDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(joint.displayName)
                    .font(.caption2.weight(.semibold))
                
                Spacer()
                
                if let matchPercent = joint.matchPercent {
                    Text(String(format: "khớp %.0f%%", matchPercent))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(percentColor(matchPercent))
                } else {
                    Text("Thiếu dữ liệu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let matchPercent = joint.matchPercent {
                ProgressView(value: matchPercent, total: 100)
                    .tint(percentColor(matchPercent))
            }
            
            HStack(spacing: 10) {
                Label(joint.isPositionValidInFrame ? "Vị trí OK" : "Cần chú ý", systemImage: joint.isPositionValidInFrame ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(joint.isPositionValidInFrame ? .green : .orange)
                Text("Confidence: \(Int(joint.currentConfidence * 100))% (ảnh) / \(Int(joint.referenceConfidence * 100))% (mẫu)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            
            if let warning = joint.positionWarning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    PoseAnalysisView(referenceStore: ReferenceImageStore())
}
