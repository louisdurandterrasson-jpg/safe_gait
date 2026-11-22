"""Pont YOLOv8 -> VideoPose3D.

Usage : python bridge_yolo_to_vp3d.py <coordonnees.csv> <video.mp4>
Sortie : data/data_2d_custom_ma_marche.npz (à placer dans le dossier data/ de VideoPose3D)
"""
import numpy as np
import csv
import cv2
import os
import matplotlib

import argparse

# --- CONFIGURATION ---
parser = argparse.ArgumentParser(description="Convertit les points 2D YOLOv8 (CSV) au format d'entrée de VideoPose3D (.npz)")
parser.add_argument("csv_yolo", help="CSV des 17 points COCO détectés par YOLOv8 (séparateur ';')")
parser.add_argument("video", help="Vidéo source (pour lire la résolution)")
args = parser.parse_args()
fichier_csv_yolo = args.csv_yolo  # Chemin vers CSV YOLO
fichier_video = args.video        # Fichier vidéo
nom_video_interne = "ma_marche"  # Nom utilisé par VideoPose3D
# ---------------------

print("Lecture de la vidéo pour récupérer la résolution...")
cap = cv2.VideoCapture(fichier_video)
if not cap.isOpened():
    print(f"ERREUR : Impossible de lire {fichier_video}. Vérifie le chemin.")
    exit()
    
largeur = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
hauteur = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
cap.release()
print(f"Résolution vidéo : {largeur}x{hauteur}")

print("Lecture du fichier CSV...")
keypoints_list = []

with open(fichier_csv_yolo, 'r') as f:
    reader = csv.reader(f, delimiter=';')
    next(reader)  # Sauter l'en-tête
    
    for row in reader:
        # Extraire les 17 points
        frame_keypoints = []
        for i in range(17):
            idx_x = 2 + (i * 3)
            idx_y = 3 + (i * 3)

            x_norm = float(row[idx_x])
            y_norm = float(row[idx_y])
            
            # Convertir les pourcentages en pixels réels
            x_pixel = x_norm * largeur
            y_pixel = y_norm * hauteur
            
            frame_keypoints.append([x_pixel, y_pixel])
            
        keypoints_list.append(frame_keypoints)

keypoints_array = np.array(keypoints_list, dtype=np.float32)

# 1. Dictionnaire des positions (Note: on le met dans une liste car c'est la "Caméra 0")
data_dict = {
    nom_video_interne: {
        "custom": [keypoints_array]
    }
}

# 2. Métadonnées blindées avec la structure "cameras" exigée par VideoPose3D
metadata_dict = {
    'layout_name': 'coco',
    'num_joints': 17,
    'keypoints_symmetry': [
        [1, 3, 5, 7, 9, 11, 13, 15],  # Côté gauche
        [2, 4, 6, 8, 10, 12, 14, 16]  # Côté droit
    ],
    'video_metadata': {
        nom_video_interne: {
            "custom": {
                # On met les dimensions à la racine et dans la liste des caméras
                # pour satisfaire toutes les versions possibles de VideoPose3D
                'w': largeur,
                'h': hauteur,
                'res_w': largeur,
                'res_h': hauteur,
                'cameras': [
                    {
                        'id': 'cam0',
                        'w': largeur,
                        'h': hauteur,
                        'res_w': largeur,
                        'res_h': hauteur
                    }
                ]
            }
        }
    }
}

os.makedirs("data", exist_ok=True)

fichier_sortie = "data/data_2d_custom_ma_marche.npz"
np.savez_compressed(fichier_sortie, positions_2d=data_dict, metadata=metadata_dict)

print(f"Succès ! Fichier généré : {fichier_sortie}")
