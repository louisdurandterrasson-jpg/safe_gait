//
//  PoseManager.swift
//  SAFE_GAIT2
//

import SwiftUI
import Combine
import Foundation
import ARKit
import MLKitVision
import MLKitPoseDetectionAccurate

class PoseManager: NSObject, ARSessionDelegate, ObservableObject {
    
    private var poseDetector: PoseDetector
    @Published var isRecording = false
    
    // Le dictionnaire qui met à jour l'écran
    @Published var detectedPoints3D: [String: SIMD3<Float>] = [:]
    
    // Variables pour la gestion des fichiers CSV et TXT
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var currentBaseFileName: String = ""
    
    private var isProcessingFrame = false
    private let ciContext = CIContext()
    
    override init() {
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = .stream
        self.poseDetector = PoseDetector.poseDetector(options: options)
        super.init()
    }
    
    // MARK: - Gestion de l'enregistrement (CSV & Notes)
    
    func startRecording() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        self.currentBaseFileName = "SAFE_GAIT_3D_\(formatter.string(from: Date()))"
        let fileName = "\(currentBaseFileName).csv"
        
        self.fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        let header = "timestamp,joint_name,x,y,z\n"
        
        do {
            try header.write(to: self.fileURL!, atomically: true, encoding: .utf8)
            self.fileHandle = try FileHandle(forWritingTo: self.fileURL!)
            self.isRecording = true
            print(" Début de l'enregistrement")
        } catch { print(" Erreur : \(error)") }
    }
    
    func stopRecording(withNotes notes: String = "") -> [URL] {
        self.isRecording = false
        fileHandle?.closeFile()
        fileHandle = nil
        print(" Fin de l'enregistrement")
        
        var exportedFiles: [URL] = []
        if let csvURL = fileURL { exportedFiles.append(csvURL) }
        
        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalNotes.isEmpty {
            let txtFileName = "\(currentBaseFileName)_notes.txt"
            let txtURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(txtFileName)
            do {
                try finalNotes.write(to: txtURL, atomically: true, encoding: .utf8)
                exportedFiles.append(txtURL)
            } catch { }
        }
        return exportedFiles
    }
    
    // MARK: - Analyse 3D
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        let pixelBuffer = frame.capturedImage
        guard let depthMap = frame.sceneDepth?.depthMap else {
            isProcessingFrame = false; return
        }
        
        let camera = frame.camera
        // On prend la vraie taille physique de l'image vue par le capteur
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            isProcessingFrame = false; return
        }
        
        let visionImage = VisionImage(image: UIImage(cgImage: cgImage))
        visionImage.orientation = .right
        
        poseDetector.process(visionImage) { [weak self] poses, error in
            guard let self = self else { return }
            defer { self.isProcessingFrame = false }
            
            guard error == nil, let poses = poses, !poses.isEmpty, let pose = poses.first else {
                DispatchQueue.main.async { self.detectedPoints3D.removeAll() }
                return
            }
            
            var points3D: [String: SIMD3<Float>] = [:]
            let cameraTransform = camera.transform
            
            // On crée le timestamp pour la ligne CSV
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            
            for landmark in pose.landmarks {
                guard landmark.inFrameLikelihood > 0.6 else { continue }
                
                // 1. MLKit nous donne les coordonnées parfaites du capteur
                let sensorPoint = CGPoint(x: landmark.position.x, y: landmark.position.y)
                let jointName = landmark.type.rawValue
                
                // 2. On lit la profondeur exacte et on crée la 3D
                if let depthZ = self.getDepth(from: depthMap, at: sensorPoint, imageSize: imageSize),
                   let point3DCamera = self.unproject(point2D: sensorPoint, depthZ: depthZ, camera: camera) {
                    
                    // 3. La matrice de la caméra place le point parfaitement dans la pièce
                    let point4D = SIMD4<Float>(point3DCamera.x, point3DCamera.y, point3DCamera.z, 1.0)
                    let pointWorld = cameraTransform * point4D
                    let final3DPoint = SIMD3<Float>(pointWorld.x, pointWorld.y, pointWorld.z)
                    
                    points3D[jointName] = final3DPoint
                    
                    // Si on enregistre, on écrit les coordonnées exactes en temps réel
                    if self.isRecording {
                        let line = "\(timestamp),\(jointName),\(final3DPoint.x),\(final3DPoint.y),\(final3DPoint.z)\n"
                        if let data = line.data(using: .utf8) { self.fileHandle?.write(data) }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.detectedPoints3D = points3D
            }
        }
    }
    
    // MARK: - Les Mathématiques du LiDAR
    
    private func getDepth(from depthMap: CVPixelBuffer, at sensorPoint: CGPoint, imageSize: CGSize) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let scaleX = CGFloat(depthWidth) / imageSize.width
        let scaleY = CGFloat(depthHeight) / imageSize.height
        
        let depthX = Int(sensorPoint.x * scaleX)
        let depthY = Int(sensorPoint.y * scaleY)
        
        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else { return nil }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pixelOffset = (depthY * bytesPerRow) + (depthX * MemoryLayout<Float32>.stride)
        let depthPointer = baseAddress.advanced(by: pixelOffset).assumingMemoryBound(to: Float32.self)
        
        let depthValue = depthPointer.pointee
        return depthValue > 0.1 ? depthValue : nil
    }
    
    // La projection sténopé classique (Pur Apple)
    private func unproject(point2D: CGPoint, depthZ: Float, camera: ARCamera) -> SIMD3<Float>? {
        let intrinsics = camera.intrinsics
        let fx = intrinsics[0][0]; let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]; let cy = intrinsics[2][1]
        
        let x = (Float(point2D.x) - cx) * depthZ / fx
        let y = -(Float(point2D.y) - cy) * depthZ / fy
        let z = -depthZ
        
        return SIMD3<Float>(x, y, z)
    }
}
