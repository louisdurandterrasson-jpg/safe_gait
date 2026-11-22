//
//  PoseLogger.swift
//  SAFE_GAIT2
//

import Foundation
import MLKitPoseDetectionAccurate
import MLKitVision

class PoseLogger {
    private var fileHandle: FileHandle?
    private var fileURL: URL // Variable pour stocker le chemin du fichier
    
    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "acquisition_\(formatter.string(from: Date())).csv"
        
        // 1. On définit le chemin complet
        self.fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        // 2. On écrit l'en-tête
        let header = "timestamp,landmark_id,x,y,z,confidence\n"
        try? header.write(to: self.fileURL, atomically: true, encoding: .utf8)
        
        // 3. On ouvre le robinet pour écrire dedans
        self.fileHandle = try? FileHandle(forWritingTo: self.fileURL)
        
        // 4. Affiche le chemin dans la console pour débugger
        print(" FICHIER CRÉÉ ICI : \(self.fileURL.path)")
    }
    
    func logPose(_ pose: Pose) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        for landmark in pose.landmarks {
            let pos3D = landmark.position
            let data = "\(timestamp),\(landmark.type.rawValue),\(pos3D.x),\(pos3D.y),\(pos3D.z),\(landmark.inFrameLikelihood)\n"
            
            // Écriture en bout de fichier
            fileHandle?.seekToEndOfFile()
            if let dataBytes = data.data(using: .utf8) {
                fileHandle?.write(dataBytes)
            }
        }
    }
    
    func stop() {
        fileHandle?.closeFile()
    }
    
    func getFilePath() -> URL {
        return self.fileURL
    }
}
