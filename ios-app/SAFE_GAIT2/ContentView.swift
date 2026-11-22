//
//  ContentView.swift
//  SAFE_GAIT2
//

import SwiftUI

// Structure utilitaire pour pouvoir partager plusieurs fichiers (CSV + TXT)
struct ShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView: View {
    @StateObject private var poseManager = PoseManager()
    
    // Variables pour l'interface de notes et de partage
    @State private var filesToShare: ShareFiles?
    @State private var showNotesSheet = false
    @State private var patientNotes = ""
    
    var body: some View {
        ZStack {
            // 1. La Caméra AR en plein écran (Le Stickman)
            CameraView(poseManager: poseManager)
                .edgesIgnoringSafeArea(.all)
            
            // 2. L'interface par-dessus la caméra
            VStack {
                
                Spacer() // Pousse le bouton vers le bas
                
                // Le gros bouton d'action
                Button(action: {
                    handleMainButtonTap()
                }) {
                    Text(poseManager.isRecording ? "ARRÊTER L'ACQUISITION" : "DÉMARRER L'ACQUISITION")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(poseManager.isRecording ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .scaleEffect(poseManager.isRecording ? 0.98 : 1.0)
                        .animation(poseManager.isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: poseManager.isRecording)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        // 3. La fenêtre de notes cliniques (S'ouvre quand on arrête l'enregistrement)
        .sheet(isPresented: $showNotesSheet) {
            NavigationView {
                VStack(alignment: .leading) {
                    Text("Observations sur le patient")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    Text("Indiquez toute information utile (utilisation d'une canne, fatigue, douleurs...)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    TextEditor(text: $patientNotes)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding()
                    
                    Button(action: {
                        finishAndExport()
                    }) {
                        Text("Valider et Exporter")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .navigationBarTitle("Notes cliniques", displayMode: .inline)
                .navigationBarItems(trailing: Button("Ignorer") {
                    patientNotes = ""
                    finishAndExport()
                })
            }
        }
        // 4. La fenêtre de partage iOS (AirDrop, Mail...)
        .sheet(item: $filesToShare) { shareItem in
            ShareSheet(items: shareItem.urls)
        }
    }
    
    // MARK: - Actions des boutons
    
    func handleMainButtonTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred() // Petite vibration haptique
        
        if poseManager.isRecording {
            // Au lieu de couper sec, on ouvre la page de notes
            showNotesSheet = true
        } else {
            // On démarre un nouvel enregistrement
            patientNotes = ""
            poseManager.startRecording()
        }
    }
    
    func finishAndExport() {
        showNotesSheet = false // On ferme la feuille
        
        // On demande au Manager d'arrêter et de générer les fichiers (CSV + TXT)
        let exportedURLs = poseManager.stopRecording(withNotes: patientNotes)
        
        // Petit délai d'une demi-seconde pour laisser l'animation de la feuille se terminer proprement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.filesToShare = ShareFiles(urls: exportedURLs)
        }
    }
}
