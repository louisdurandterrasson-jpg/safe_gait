//
//  CameraView.swift
//  SAFE_GAIT2
//

import SwiftUI
import ARKit
import RealityKit

struct CameraView: UIViewRepresentable {
    @ObservedObject var poseManager: PoseManager
    
    // Le dictionnaire pour savoir quels points relier entre eux
    static let skeletonConnections: [[String]] = [
        ["Nose", "LeftEye"], ["Nose", "RightEye"],
        ["LeftEye", "LeftEar"], ["RightEye", "RightEar"],
        ["LeftShoulder", "RightShoulder"],
        ["LeftShoulder", "LeftHip"], ["RightShoulder", "RightHip"],
        ["LeftHip", "RightHip"],
        ["LeftShoulder", "LeftElbow"], ["LeftElbow", "LeftWrist"],
        ["LeftWrist", "LeftPinkyFinger"], ["LeftWrist", "LeftIndexFinger"], ["LeftWrist", "LeftThumb"],
        ["LeftPinkyFinger", "LeftIndexFinger"],
        ["RightShoulder", "RightElbow"], ["RightElbow", "RightWrist"],
        ["RightWrist", "RightPinkyFinger"], ["RightWrist", "RightIndexFinger"], ["RightWrist", "RightThumb"],
        ["RightPinkyFinger", "RightIndexFinger"],
        ["LeftHip", "LeftKnee"], ["LeftKnee", "LeftAnkle"],
        ["LeftAnkle", "LeftHeel"], ["LeftAnkle", "LeftToe"],
        ["LeftHeel", "LeftToe"],
        ["RightHip", "RightKnee"], ["RightKnee", "RightAnkle"],
        ["RightAnkle", "RightHeel"], ["RightAnkle", "RightToe"],
        ["RightHeel", "RightToe"]
    ]
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth) // On allume le LiDAR
        }
        
        arView.session.delegate = poseManager
        arView.session.run(config)
        
        // On crée un point d'ancrage invisible au centre de la pièce pour y accrocher notre squelette
        let rootAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(rootAnchor)
        context.coordinator.skeletonRoot = rootAnchor
        
        return arView
    }
    
    // Cette fonction est appelée automatiquement par SwiftUI dès que poseManager.detectedPoints3D change
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateSkeleton(points: poseManager.detectedPoints3D)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Affichage 3D du skeleton (Coordinator)
    class Coordinator: NSObject {
        var skeletonRoot: AnchorEntity?
        var jointEntities: [String: ModelEntity] = [:]
        var lineEntities: [String: ModelEntity] = [:]
        let skeletonColor: UIColor = .cyan
        
        func updateSkeleton(points: [String: SIMD3<Float>]) {
            guard let root = skeletonRoot else { return }
            
            // 1. Dessiner les articulations (Sphères)
            for (jointName, position) in points {
                if let entity = jointEntities[jointName] {
                    entity.position = position
                    entity.isEnabled = true
                } else {
                    let mesh = MeshResource.generateSphere(radius: 0.012)
                    let material = SimpleMaterial(color: skeletonColor, isMetallic: false)
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    entity.position = position
                    root.addChild(entity)
                    jointEntities[jointName] = entity
                }
            }
            
            // 2. Dessiner les os (Cylindres)
            for connection in CameraView.skeletonConnections {
                let joint1Name = connection[0]
                let joint2Name = connection[1]
                
                if let pos1 = points[joint1Name], let pos2 = points[joint2Name] {
                    let lineKey = "\(joint1Name)-\(joint2Name)"
                    if let lineEntity = lineEntities[lineKey] {
                        updateLine(lineEntity, from: pos1, to: pos2)
                        lineEntity.isEnabled = true
                    } else {
                        let lineEntity = createLineEntity(thickness: 0.005, color: skeletonColor)
                        updateLine(lineEntity, from: pos1, to: pos2)
                        root.addChild(lineEntity)
                        lineEntities[lineKey] = lineEntity
                    }
                } else {
                    let lineKey = "\(joint1Name)-\(joint2Name)"
                    lineEntities[lineKey]?.isEnabled = false
                }
            }
            
            // 3. Masquer ce que l'IA ne voit plus
            for (jointName, entity) in jointEntities {
                if points[jointName] == nil { entity.isEnabled = false }
            }
        }
        
        // Outil pour créer un cylindre
        func createLineEntity(thickness: Float, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateCylinder(height: 1.0, radius: thickness)
            let material = SimpleMaterial(color: color, isMetallic: false)
            return ModelEntity(mesh: mesh, materials: [material])
        }
        
        // Outil pour placer et étirer le cylindre entre deux points
        func updateLine(_ lineEntity: ModelEntity, from pos1: SIMD3<Float>, to pos2: SIMD3<Float>) {
            let vector = pos2 - pos1
            let distance = length(vector)
            lineEntity.position = (pos1 + pos2) / 2.0
            lineEntity.scale = SIMD3<Float>(1.0, distance, 1.0)
            
            let defaultOrientation = SIMD3<Float>(0, 1, 0)
            let normalizedVector = normalize(vector)
            lineEntity.orientation = simd_quaternion(defaultOrientation, normalizedVector)
        }
    }
}
