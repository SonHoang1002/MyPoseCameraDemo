//
//  ContentView.swift
//  MtPoseCameraDemo26
//
//  Created by sonmac on 19/7/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var referenceImageStore = ReferenceImageStore()
    
    var body: some View {
        TabView {
            VideoExtractorView()
                .tabItem {
                    Label("Extractor", systemImage: "video.badge.plus")
                }
            
            ImageCompareView()
                .tabItem {
                    Label("Compare", systemImage: "rectangle.on.rectangle")
                }
            
            HybridCaptureView()
                .tabItem {
                    Label("Hybrid", systemImage: "camera.aperture")
                }
            
            PoseAnalysisView(referenceStore: referenceImageStore)
                .tabItem {
                    Label("Pose", systemImage: "figure.walk")
                }
            
            LivePoseTrackingView(referenceStore: referenceImageStore)
                .tabItem {
                    Label("Live Pose", systemImage: "figure.walk.motion")
                }
        }
    }
}

#Preview {
    ContentView()
}
