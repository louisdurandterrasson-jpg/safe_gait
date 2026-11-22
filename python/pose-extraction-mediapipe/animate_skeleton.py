# Usage : python animate_skeleton.py fichier1.csv [fichier2.csv ...]
#
# INFO : Ce script est à utiliser APRÈS avoir récupéré et généré 
# le fichier .csv contenant les points d'intérêts via MediaPipe.
# Il permet de lire les données, de les fusionner et de lancer une 
# animation du squelette (en 2D ou 3D).

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.widgets import Slider
import sys

# CONFIGURATION UNIVERSELLE
# Fichiers CSV passés en argument
FICHIERS_CSV = sys.argv[1:]
if not FICHIERS_CSV:
    print("Usage : python animate_skeleton.py fichier1.csv [fichier2.csv ...]")
    sys.exit(1)

INVERSER_X_Y = True
TETE_EN_HAUT = True
FACTEUR_Z = 0.2
VITESSE_LECTURE = 30

BONES = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24),
    (23, 25), (25, 27), (24, 26), (26, 28),
    (27, 29), (29, 31), (28, 30), (30, 32)
]

def charger_les_fichiers(fichiers):
    toutes_les_frames = []
    nb_points = 33
    global_est_3d = None
    
    for fichier in fichiers:
        print(f"Analyse du fichier : {fichier}...")
        try:
            df = pd.read_csv(fichier)
        except FileNotFoundError:
            print(f"Attention : Fichier introuvable, il sera ignoré -> {fichier}")
            continue
            
        colonnes = df.columns.tolist()
        
        if "Point_32_X" not in colonnes:
            print(f"Format incorrect pour {fichier} (ML Kit 33 points attendu), ignoré.")
            continue
            
        est_3d = "Point_0_Z" in colonnes
        print(f"  -> Format Google ML Kit / MediaPipe détecté. Dimension : {'3D' if est_3d else '2D'}")
        
        if global_est_3d is None:
            global_est_3d = est_3d
            
        for index, row in df.iterrows():
            frame_data = {}
            for i in range(nb_points):
                if f'Point_{i}_X' not in row:
                    frame_data[i] = (0, 0, 0, 0)
                    continue
                    
                x_brut = row[f'Point_{i}_X']
                y_brut = row[f'Point_{i}_Y']
                
                x_final = y_brut if INVERSER_X_Y else x_brut
                y_final = x_brut if INVERSER_X_Y else y_brut
                y_final = -y_final if TETE_EN_HAUT else y_final
                
                if global_est_3d and f'Point_{i}_Z' in row:
                    z_final = row[f'Point_{i}_Z'] * FACTEUR_Z
                else:
                    z_final = 0.0 
                    
                confiance = row.get(f'Point_{i}_Visibilite', row.get(f'Point_{i}_Confiance', 1.0))
                frame_data[i] = (x_final, y_final, z_final, confiance)
                
            toutes_les_frames.append(frame_data)
            
    print(f"\nFusion terminée ! {len(toutes_les_frames)} images au total prêtes pour l'animation.")
    return toutes_les_frames, nb_points, BONES, global_est_3d

def update_graph(num, frames, scatter, lines, text_time, nb_points, bones, est_3d):
    frame = frames[num]
    xs, ys, zs = [], [], []
    valid_points = []
    
    for i in range(nb_points):
        x, y, z, conf = frame[i]
        if conf > 0.5:
            xs.append(x)
            ys.append(y)
            zs.append(z)
            valid_points.append(i)
            
    if len(xs) > 0:
        if est_3d:
            scatter._offsets3d = (xs, ys, zs)
        else:
            scatter.set_offsets(np.c_[xs, ys])
    else:
        if est_3d: scatter._offsets3d = ([], [], [])
        else: scatter.set_offsets(np.empty((0, 2)))
        
    for idx, bone in enumerate(bones):
        j1, j2 = bone
        if j1 in valid_points and j2 in valid_points:
            x1, y1, z1, _ = frame[j1]
            x2, y2, z2, _ = frame[j2]
            
            lines[idx].set_data([x1, x2], [y1, y2])
            if est_3d: lines[idx].set_3d_properties([z1, z2])
        else:
            lines[idx].set_data([], [])
            if est_3d: lines[idx].set_3d_properties([])
            
    text_time.set_text(f"Image : {num} / {len(frames)-1}")
    return [scatter, text_time] + lines

def main():
    frames, nb_points, bones, est_3d = charger_les_fichiers(FICHIERS_CSV)
    
    if len(frames) == 0:
        print("Erreur : Aucun fichier valide n'a pu être chargé.")
        sys.exit(1)
        
    all_x, all_y, all_z = [], [], []
    for f in frames:
        for i in range(nb_points):
            if f[i][3] > 0.5:
                all_x.append(f[i][0])
                all_y.append(f[i][1])
                all_z.append(f[i][2])
                
    fig = plt.figure(figsize=(10, 8))
    plt.subplots_adjust(bottom=0.25)
    
    if est_3d:
        ax = fig.add_subplot(111, projection='3d')
        ax.set_zlabel('Hauteur (Z)')
        
        max_range = max(max(all_x)-min(all_x), max(all_y)-min(all_y), max(all_z)-min(all_z))
        mid_x = (max(all_x)+min(all_x)) * 0.5
        mid_y = (max(all_y)+min(all_y)) * 0.5
        mid_z = (max(all_z)+min(all_z)) * 0.5
        ax.set_xlim(mid_x - max_range/2, mid_x + max_range/2)
        ax.set_ylim(mid_y - max_range/2, mid_y + max_range/2)
        ax.set_zlim(mid_z - max_range/2, mid_z + max_range/2)
        ax.set_box_aspect((1, 1, 1))
        ax.view_init(elev=15, azim=-60)
        
        text_time = ax.text2D(0.05, 0.95, "", transform=ax.transAxes)
    else:
        ax = fig.add_subplot(111)
        ax.set_xlim(min(all_x) - 0.1, max(all_x) + 0.1)
        ax.set_ylim(min(all_y) - 0.1, max(all_y) + 0.1)
        ax.set_aspect('equal')
        
        text_time = ax.text(0.05, 0.95, "", transform=ax.transAxes)
        
    ax.set_title(f"SafeGait - Playlist ({'3D' if est_3d else '2D'})")
    ax.set_xlabel('Largeur (X)')
    ax.set_ylabel('Profondeur / Y' if est_3d else 'Hauteur (Y)')

    if est_3d:
        scatter = ax.scatter([], [], [], c='red', s=40)
        lines = [ax.plot([], [], [], c='green', linewidth=3)[0] for _ in bones]
    else:
        scatter = ax.scatter([], [], c='red', s=40)
        lines = [ax.plot([], [], c='green', linewidth=3)[0] for _ in bones]

    ax_frame = plt.axes([0.15, 0.1, 0.7, 0.03])
    frame_slider = Slider(ax_frame, 'Image', 0, len(frames)-1, valinit=0, valstep=1)
    
    def on_slider_update(val):
        update_graph(int(val), frames, scatter, lines, text_time, nb_points, bones, est_3d)
        fig.canvas.draw_idle()
        
    frame_slider.on_changed(on_slider_update)

    ani = animation.FuncAnimation(
        fig, update_graph, frames=len(frames), 
        fargs=(frames, scatter, lines, text_time, nb_points, bones, est_3d),
        interval=VITESSE_LECTURE, blit=False
    )
    
    def update_slider(num):
        frame_slider.set_val(num)
        
    ani_slider = animation.FuncAnimation(fig, update_slider, frames=len(frames), interval=VITESSE_LECTURE, blit=False)
    
    plt.show()

if __name__ == '__main__':
    main()