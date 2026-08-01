//
//  ImageCompareViewModel.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI
import PhotosUI
internal import Combine

@MainActor
class ImageCompareViewModel: ObservableObject {
    // MARK: - Slot 1
    @Published var selectedItem1: PhotosPickerItem? {
        didSet { Task { await load(item: selectedItem1, slot: 1) } }
    }
    @Published var image1: UIImage?
    @Published var report1: ImageQualityReport?
    @Published var isLoading1 = false
    
    // MARK: - Slot 2
    @Published var selectedItem2: PhotosPickerItem? {
        didSet { Task { await load(item: selectedItem2, slot: 2) } }
    }
    @Published var image2: UIImage?
    @Published var report2: ImageQualityReport?
    @Published var isLoading2 = false
    
    // MARK: - Error
    @Published var showError = false
    @Published var errorMessage: String?
    
    var comparison: ImageComparisonResult? {
        guard let report1, let report2 else { return nil }
        return ImageQualityAnalyzer.compare(report1, report2, nameA: "Ảnh 1", nameB: "Ảnh 2")
    }
    
    private func load(item: PhotosPickerItem?, slot: Int) async {
        guard let item else { return }
        
        if slot == 1 { isLoading1 = true } else { isLoading2 = true }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                throw NSError(domain: "ImageCompare", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không đọc được dữ liệu ảnh"])
            }
            
            let report = ImageQualityAnalyzer.analyze(uiImage, originalFileSizeBytes: data.count)
            
            if slot == 1 {
                self.image1 = uiImage
                self.report1 = report
                self.isLoading1 = false
            } else {
                self.image2 = uiImage
                self.report2 = report
                self.isLoading2 = false
            }
            
        } catch {
            if slot == 1 { isLoading1 = false } else { isLoading2 = false }
            errorMessage = "Import ảnh thất bại: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func reset() {
        selectedItem1 = nil
        selectedItem2 = nil
        image1 = nil
        image2 = nil
        report1 = nil
        report2 = nil
    }
}
