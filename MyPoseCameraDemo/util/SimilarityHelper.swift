//
//  SimilarityHelper.swift
//  MtPoseCameraDemo26
//
//  Tính % tương đồng giữa 2 ảnh theo 2 hướng:
//  1) Feature Print (VNGenerateImageFeaturePrintRequest) — so khớp hình ảnh/object tổng thể.
//  2) Pose similarity — so khớp tư thế dựa trên các điểm khớp cơ thể đã phát hiện.
//
//  LƯU Ý QUAN TRỌNG: Apple KHÔNG định nghĩa thang % chính thức cho khoảng cách feature print
//  hay cho sai khác giữa các điểm pose. Các công thức quy đổi ra % dưới đây là HEURISTIC
//  (ước lượng dựa trên kinh nghiệm), dùng để tham khảo trực quan — không phải phép đo
//  tương đồng "chính xác tuyệt đối" được Apple xác nhận.
//

import Vision
import CoreGraphics
import CoreVideo

enum SimilarityHelper {
    
    // MARK: - Feature Print
    
    static func generateFeaturePrint(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return runFeaturePrintRequest(handler: handler)
    }
    
    static func generateFeaturePrint(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return runFeaturePrintRequest(handler: handler)
    }
    
    private static func runFeaturePrintRequest(handler: VNImageRequestHandler) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
    
    /// % tương đồng tổng thể giữa 2 ảnh (0-100), dựa trên khoảng cách feature print.
    /// Khoảng cách càng nhỏ → ảnh càng giống nhau. Công thức quy đổi là heuristic.
    static func featurePrintSimilarityPercent(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Double? {
        var distance: Float = 0
        do {
            try a.computeDistance(&distance, to: b)
        } catch {
            return nil
        }
        let clamped = max(0, min(2.0, Double(distance)))
        return (1 - clamped / 2.0) * 100
    }
    
    // MARK: - Pose similarity
    
    /// % khớp tư thế giữa 2 tập điểm cơ thể (0-100), hoặc nil nếu không đủ dữ liệu chung.
    ///
    /// QUAN TRỌNG: nhận thêm `frameSizeA`/`frameSizeB` (kích thước THỰC của từng ảnh/frame).
    /// Vision trả về toạ độ normalized (0...1) tính riêng theo width và height của ẢNH GỐC —
    /// nếu 2 ảnh có tỉ lệ khung hình khác nhau (ví dụ ảnh mẫu vuông 1:1 nhưng camera đang zoom
    /// ra tỉ lệ 9:16), thì 1 đơn vị normalized theo trục X và trục Y sẽ tương ứng với khoảng
    /// cách PIXEL THỰC khác nhau giữa 2 ảnh. Nếu so sánh trực tiếp toạ độ normalized mà không quy
    /// đổi, kết quả sẽ bị méo (sai lệch theo đúng độ lệch tỉ lệ khung hình, KHÔNG phản ánh đúng
    /// dáng người). Hàm này quy đổi mỗi bộ khớp về pixel THEO KÍCH THƯỚC ẢNH CỦA CHÍNH NÓ trước,
    /// rồi mới chuẩn hoá theo chiều dài "cột sống" (neck→root) của chính ảnh đó — nhờ vậy kết quả
    /// không phụ thuộc vào độ phân giải hay tỉ lệ khung hình của từng ảnh.
    static func poseSimilarityPercent(
        _ jointsA: [BodyJointPoint],
        frameSizeA: CGSize,
        _ jointsB: [BodyJointPoint],
        frameSizeB: CGSize,
        minConfidence: Float = 0.3
    ) -> Double? {
        guard frameSizeA.width > 0, frameSizeA.height > 0,
              frameSizeB.width > 0, frameSizeB.height > 0 else { return nil }
        
        let dictA = Dictionary(uniqueKeysWithValues: jointsA.map { ($0.jointName, $0) })
        let dictB = Dictionary(uniqueKeysWithValues: jointsB.map { ($0.jointName, $0) })
        
        guard let neckA = dictA[.neck], let rootA = dictA[.root],
              let neckB = dictB[.neck], let rootB = dictB[.root] else {
            return nil
        }
        
        func toPixel(_ p: CGPoint, size: CGSize) -> CGPoint {
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        
        let neckPxA = toPixel(neckA.location, size: frameSizeA)
        let rootPxA = toPixel(rootA.location, size: frameSizeA)
        let neckPxB = toPixel(neckB.location, size: frameSizeB)
        let rootPxB = toPixel(rootB.location, size: frameSizeB)
        
        // Chuẩn hoá theo chiều dài "cột sống" (neck -> root) TÍNH TRONG PIXEL THỰC của từng ảnh
        // — đây là bước quan trọng để bất biến với cả độ phân giải LẪN tỉ lệ khung hình khác nhau.
        let scaleA = distance(neckPxA, rootPxA)
        let scaleB = distance(neckPxB, rootPxB)
        guard scaleA > 0.5, scaleB > 0.5 else { return nil }
        
        var totalDistance: Double = 0
        var matchedCount = 0
        
        for (name, pointA) in dictA {
            guard let pointB = dictB[name] else { continue }
            guard pointA.confidence >= minConfidence, pointB.confidence >= minConfidence else { continue }
            
            let pxA = toPixel(pointA.location, size: frameSizeA)
            let pxB = toPixel(pointB.location, size: frameSizeB)
            
            let normalizedA = normalize(pxA, origin: rootPxA, scale: scaleA)
            let normalizedB = normalize(pxB, origin: rootPxB, scale: scaleB)
            
            totalDistance += Double(distance(normalizedA, normalizedB))
            matchedCount += 1
        }
        
        guard matchedCount >= 4 else { return nil }
        
        let avgDistance = totalDistance / Double(matchedCount)
        return max(0, min(100, (1 - avgDistance / 1.2) * 100))
    }
    
    // MARK: - Phân tích chi tiết TỪNG ĐIỂM (thay vì chỉ 1 con số % tổng)
    
    /// So sánh chi tiết từng khớp giữa ảnh hiện tại và ảnh mẫu, gộp theo nhóm bộ phận cơ thể.
    /// Dùng cùng phép quy đổi normalized→pixel như `poseSimilarityPercent` để không bị méo
    /// khi 2 ảnh có tỉ lệ khung hình khác nhau (zoom, xoay máy...).
    ///
    /// - Parameters:
    ///   - currentJoints: các khớp phát hiện được ở ảnh/frame ĐANG XEM (sẽ được đánh giá thêm
    ///     về việc vị trí trong khung hình có "an toàn" hay không).
    ///   - frameMargin: khoảng cách tính từ mép khung hình (theo tỉ lệ 0...1) được coi là "sát mép".
    static func detailedJointComparison(
        currentJoints: [BodyJointPoint],
        currentFrameSize: CGSize,
        referenceJoints: [BodyJointPoint],
        referenceFrameSize: CGSize,
        minConfidence: Float = 0.3,
        frameMargin: CGFloat = 0.05
    ) -> [BodyPartGroupComparison]? {
        guard currentFrameSize.width > 0, currentFrameSize.height > 0,
              referenceFrameSize.width > 0, referenceFrameSize.height > 0 else { return nil }
        
        let dictCurrent = Dictionary(uniqueKeysWithValues: currentJoints.map { ($0.jointName, $0) })
        let dictRef = Dictionary(uniqueKeysWithValues: referenceJoints.map { ($0.jointName, $0) })
        
        guard let neckCur = dictCurrent[.neck], let rootCur = dictCurrent[.root],
              let neckRef = dictRef[.neck], let rootRef = dictRef[.root] else {
            return nil
        }
        
        func toPixel(_ p: CGPoint, size: CGSize) -> CGPoint {
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        
        let neckPxCur = toPixel(neckCur.location, size: currentFrameSize)
        let rootPxCur = toPixel(rootCur.location, size: currentFrameSize)
        let neckPxRef = toPixel(neckRef.location, size: referenceFrameSize)
        let rootPxRef = toPixel(rootRef.location, size: referenceFrameSize)
        
        let scaleCur = distance(neckPxCur, rootPxCur)
        let scaleRef = distance(neckPxRef, rootPxRef)
        guard scaleCur > 0.5, scaleRef > 0.5 else { return nil }
        
        var details: [JointComparisonDetail] = []
        
        // Duyệt qua TẤT CẢ khớp có ở ảnh hiện tại (kể cả khi ảnh mẫu không có, để vẫn báo được
        // vị trí trong khung hình — chỉ riêng phần "so với ảnh mẫu" sẽ để nil nếu thiếu bên kia).
        for currentJoint in currentJoints {
            let refJoint = dictRef[currentJoint.jointName]
            
            var deviationPercent: Double? = nil
            if let refJoint,
               currentJoint.confidence >= minConfidence,
               refJoint.confidence >= minConfidence {
                let pxCur = toPixel(currentJoint.location, size: currentFrameSize)
                let pxRef = toPixel(refJoint.location, size: referenceFrameSize)
                
                let normalizedCur = normalize(pxCur, origin: rootPxCur, scale: scaleCur)
                let normalizedRef = normalize(pxRef, origin: rootPxRef, scale: scaleRef)
                
                let dist = Double(distance(normalizedCur, normalizedRef))
                deviationPercent = max(0, min(100, (dist / 1.2) * 100))
            }
            
            let (isValid, warning) = positionValidity(
                for: currentJoint,
                margin: frameMargin,
                minConfidence: minConfidence
            )
            
            details.append(JointComparisonDetail(
                jointName: currentJoint.jointName,
                displayName: currentJoint.displayName,
                deviationPercent: deviationPercent,
                currentConfidence: currentJoint.confidence,
                referenceConfidence: refJoint?.confidence ?? 0,
                isPositionValidInFrame: isValid,
                positionWarning: warning
            ))
        }
        
        // Gộp theo nhóm bộ phận cơ thể, sắp xếp theo thứ tự đầu → chân cho dễ đọc.
        var groupedByName: [String: (icon: String, order: Int, joints: [JointComparisonDetail])] = [:]
        for detail in details {
            let info = BodyPartGroup.groupInfo(for: detail.jointName)
            groupedByName[info.groupName, default: (info.icon, info.order, [])].joints.append(detail)
        }
        
        return groupedByName
            .map { name, value in
                BodyPartGroupComparison(groupName: name, icon: value.icon, joints: value.joints)
            }
            .sorted { a, b in
                let orderA = groupedByName[a.groupName]?.order ?? 99
                let orderB = groupedByName[b.groupName]?.order ?? 99
                return orderA < orderB
            }
    }
    
    /// Kiểm tra 1 khớp có đang nằm ở vị trí "an toàn" trong khung hình hay không:
    /// không quá sát mép (có thể đã bị cắt hình) và confidence đủ cao (không phải ước lượng mơ hồ).
    private static func positionValidity(
        for joint: BodyJointPoint,
        margin: CGFloat,
        minConfidence: Float
    ) -> (isValid: Bool, warning: String?) {
        if joint.confidence < minConfidence {
            return (false, "Độ tin cậy thấp (\(Int(joint.confidence * 100))%) — có thể đang bị khuất, vị trí chỉ là ước lượng.")
        }
        
        let p = joint.location // normalized, gốc dưới-trái theo Vision
        var edges: [String] = []
        if p.y > 1 - margin { edges.append("mép trên") }
        if p.y < margin { edges.append("mép dưới") }
        if p.x < margin { edges.append("mép trái") }
        if p.x > 1 - margin { edges.append("mép phải") }
        
        if !edges.isEmpty {
            return (false, "Đang sát \(edges.joined(separator: ", ")) khung hình — có thể bị cắt mất nếu zoom/dịch chuyển thêm.")
        }
        
        return (true, nil)
    }
    
    private static func normalize(_ point: CGPoint, origin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
    
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
}
