//
//  LivePoseTrackingView.swift
//  MtPoseCameraDemo26
//
//  Tab: preview camera trực tiếp + vẽ skeleton/face landmark theo thời gian thực
//  ngay trên màn hình, bao gồm cả các điểm có độ tin cậy thấp (khả năng bị khuất).
//

import SwiftUI
import PhotosUI

struct LivePoseTrackingView: View {
    @StateObject private var viewModel = LivePoseTrackingViewModel()
    @ObservedObject var referenceStore: ReferenceImageStore
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        referenceImportSection
                        cameraSection
                        liveQualitySection
                        if referenceStore.hasReference {
                            liveSimilaritySection
                            
                            if let detailedGroups = detailedComparison {
                                detailedJointSection(detailedGroups)
                            }
                        }
                        controlsSection
                        legendSection
                    }
                    .padding()
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Live Pose Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.attach(referenceStore: referenceStore)
                await viewModel.requestPermissionAndStart()
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
    
    // MARK: - Camera + overlay
    
    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("figure.walk.motion", "Live Camera", tint: .red)
                Spacer()
                PillBadge(text: String(format: "%.0f fps", viewModel.currentFPS), color: .blue)
            }
            
            ZStack {
                if viewModel.isSessionRunning {
                    CameraPreviewView(session: viewModel.session, videoGravity: .resizeAspect)
                    
                    PoseOverlayCanvas(
                        joints: viewModel.bodyJoints,
                        faceLandmarkGroups: viewModel.faceLandmarkGroups,
                        showLowConfidencePoints: viewModel.showLowConfidencePoints
                    )
                } else {
                    EmptyStatePlaceholder(icon: "camera.viewfinder", text: "Đang khởi tạo camera...", height: 420)
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .cardStyle()
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $viewModel.showLowConfidencePoints) {
                Label("Hiện cả điểm bị khuất / độ tin cậy thấp", systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption)
            }
            
            HStack {
                Label("\(viewModel.bodyJoints.count) body joints", systemImage: "figure.stand")
                Spacer()
                Label("\(viewModel.faceLandmarkGroups.reduce(0) { $0 + $1.count }) face points", systemImage: "face.smiling")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
    
    // MARK: - Legend
    
    private var legendSection: some View {
        HStack(spacing: 14) {
            legendDot(color: .green, text: "Rõ ràng")
            legendDot(color: .orange, text: "Không chắc chắn")
            legendDot(color: .red, text: "Có thể bị khuất")
            legendDot(color: .cyan, text: "Face")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .cardStyle()
    }
    
    // MARK: - Reference (ảnh mẫu) — DÙNG CHUNG với tab Pose Analysis
    
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
                    }
                }
            }
        }
        .cardStyle()
    }
    
    // MARK: - Live frame quality (blur, tỉ lệ khung hình, khớp bị cắt mép)
    
    private var liveQualitySection: some View {
        Group {
            if let report = viewModel.currentFrameQuality {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader("checkmark.shield", "Chất lượng frame hiện tại", tint: .teal)
                        Spacer()
                        PillBadge(text: report.verdict, color: reliabilityColor(report.overallReliabilityPercent))
                    }
                    
                    HStack(spacing: 16) {
                        if let blur = report.blur {
                            Label(blur.isLikelyBlurry ? "Có thể bị mờ" : "Đủ nét", systemImage: blur.isLikelyBlurry ? "camera.metering.unknown" : "checkmark.seal")
                                .foregroundStyle(blur.isLikelyBlurry ? .red : .green)
                        }
                        Label("\(report.visibleJointCount)/\(report.totalJointCount) khớp", systemImage: "figure.stand")
                            .foregroundStyle(.secondary)
                        Label(report.aspectRatioString, systemImage: "aspectratio")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    
                    if !report.warningMessages.isEmpty {
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
                }
                .cardStyle()
            }
        }
    }
    
    // MARK: - Live similarity
    
    private var liveSimilaritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("percent", "Độ tương thích realtime với ảnh mẫu", tint: .pink)
            
            if let reliability = viewModel.currentFrameQuality?.overallReliabilityPercent, reliability < 45 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Frame hiện tại có độ tin cậy thấp (mờ / góc khuất / thiếu khớp) — % bên dưới chỉ mang tính tham khảo.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.08)))
            }
            
            if let objectPercent = viewModel.liveObjectSimilarityPercent {
                similarityRow(title: "Object / hình ảnh tổng thể", percent: objectPercent, icon: "photo.stack")
            } else {
                Text("Đang chờ frame tiếp theo để tính độ tương đồng object...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if let posePercent = viewModel.livePoseSimilarityPercent {
                similarityRow(title: "Khớp tư thế (pose)", percent: posePercent, icon: "figure.stand")
            } else if referenceStore.hasReferencePose {
                Text("Chưa đủ điểm khớp chung đáng tin cậy để so tư thế lúc này.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if let refAspect = referenceStore.frameQuality?.aspectRatioString,
               let curAspect = viewModel.currentFrameQuality?.aspectRatioString, refAspect != curAspect {
                HStack(spacing: 6) {
                    Image(systemName: "aspectratio").font(.caption2)
                    Text("Tỉ lệ khung hình khác nhau: ảnh mẫu \(refAspect) vs camera hiện tại \(curAspect) — đã tự động quy đổi theo pixel thực, không bị méo do zoom/xoay máy.")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
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
    
    private func reliabilityColor(_ percent: Double) -> Color {
        if percent >= 75 { return .green }
        if percent >= 45 { return .orange }
        return .red
    }
    
    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
    
    // MARK: - Phân tích chi tiết từng điểm (realtime)
    
    private var detailedComparison: [BodyPartGroupComparison]? {
        guard viewModel.currentFrameSize != .zero, referenceStore.imageSize != .zero else { return nil }
        return SimilarityHelper.detailedJointComparison(
            currentJoints: viewModel.bodyJoints,
            currentFrameSize: viewModel.currentFrameSize,
            referenceJoints: referenceStore.poseResult?.bodyJoints2D ?? [],
            referenceFrameSize: referenceStore.imageSize
        )
    }
    
    private func detailedJointSection(_ groups: [BodyPartGroupComparison]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("list.bullet.rectangle", "Phân tích chi tiết từng điểm", tint: .indigo)
            
            Text("% lệch so với ảnh mẫu tính riêng cho từng khớp, kèm kiểm tra vị trí trong khung hình hiện tại.")
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
                Text("Confidence: \(Int(joint.currentConfidence * 100))%")
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
    LivePoseTrackingView(referenceStore: ReferenceImageStore())
}
