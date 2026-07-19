//
//  LiDARView.swift
//  MyPoseCameraDemo
//
//  Created by sonmac on 19/7/26.
//




import ARKit
import SwiftUI

struct LiDARView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.environmentTexturing = .automatic
        config.frameSemantics = .sceneDepth
        sceneView.session.run(config)
        sceneView.delegate = context.coordinator
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSCNViewDelegate {
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Access mesh geometry from LiDAR
                let geometry = meshAnchor.geometry
                print("Captured mesh with \(geometry.vertices.count) vertices")
            }
        }
    }
}
