"""Extraction des 33 points du squelette (MediaPipe Pose) image par image, export CSV.

Usage : python extract_pose_mediapipe.py <video.mp4> [--out donnees_squelette.csv]
"""
import argparse
import csv

import cv2
import mediapipe as mp

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("video", help="Vidéo d'entrée (marche du patient)")
parser.add_argument("--out", default="donnees_squelette.csv", help="Fichier CSV de sortie")
args = parser.parse_args()

# 1. Initialisation de MediaPipe Pose
mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils
pose = mp_pose.Pose(static_image_mode=False, min_detection_confidence=0.5, min_tracking_confidence=0.5)

# 2. Ouverture de la vidéo
video_path = args.video
cap = cv2.VideoCapture(video_path)

# 3. Préparation du fichier CSV pour sauvegarder les données
csv_file = open(args.out, mode='w', newline='')
csv_writer = csv.writer(csv_file)

# Création de l'en-tête du fichier CSV (Frame, puis X, Y, Z, Visibilité pour les 33 points)
header = ['Frame_Number']
for i in range(33):
    header.extend([f'Point_{i}_X', f'Point_{i}_Y', f'Point_{i}_Z', f'Point_{i}_Visibilite'])
csv_writer.writerow(header)

frame_count = 0

print("Début de l'analyse... Appuie sur la touche 'q' pour quitter prématurément.")

# 4. Boucle de traitement frame par frame
while cap.isOpened():
    success, frame = cap.read()
    if not success:
        print("Fin de la vidéo atteinte.")
        break
        
    frame_count += 1

    # MediaPipe a besoin d'images en couleurs RGB (OpenCV lit en BGR par défaut)
    image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(image_rgb)

    # Si un corps est détecté
    if results.pose_landmarks:
        # Dessiner le squelette sur l'image pour qu'on puisse le voir
        mp_drawing.draw_landmarks(frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS)
        
        # Extraire et sauvegarder les données pour cette image
        row_data = [frame_count]
        for landmark in results.pose_landmarks.landmark:
            row_data.extend([landmark.x, landmark.y, landmark.z, landmark.visibility])
        
        csv_writer.writerow(row_data)

    # Afficher la vidéo avec le squelette superposé
    cv2.imshow("Analyse de la marche", frame)

    # Quitter si on appuie sur 'q'
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# 5. Nettoyage et fermeture de tous les fichiers
cap.release()
csv_file.close()
cv2.destroyAllWindows()

print(f"Analyse terminée ! Les données sont sauvegardées dans '{args.out}'.")
