"""
filter_crops.py
---------------
Filtra los recortes de pizza generados por crop_pizza_images.py y selecciona
los mejores por video para subir.

Criterios de calidad:
  1. Tamano minimo (descarta recortes demasiado pequenos)
  2. Nitidez / blur (Laplacian variance — mayor = mas nitida)
  3. Brillo aceptable (descarta imagenes muy oscuras o sobreexpuestas)

Los mejores N por video (ordenados por nitidez) se copian a selected_frames/.
"""

import os
import shutil
from pathlib import Path
from collections import defaultdict

import cv2
import numpy as np

# =====================================================
#  CONFIGURACION
# =====================================================

BASE_DIR       = Path(r"C:\pizza_pipeline")
INPUT_DIR      = BASE_DIR / "cropped_frames"
OUTPUT_DIR     = BASE_DIR / "selected_frames"

# Tamano minimo del recorte en pixeles (ancho y alto)
MIN_WIDTH  = 100
MIN_HEIGHT = 100

# Nitidez: NO hay umbral minimo — se rankea y se toman las mejores.
# Las camaras IP siempre tienen menos nitidez que camaras normales,
# por eso no descartamos por blur sino que ordenamos por el.

# Brillo: porcentaje de pixeles quemados o muy oscuros permitido
MAX_OVEREXPOSED_PCT  = 0.40   # maximo 40% pixeles > 245
MAX_UNDEREXPOSED_PCT = 0.60   # maximo 60% pixeles < 20

# Maximo de imagenes a guardar por video
TOP_N = 8

# =====================================================

OUTPUT_DIR.mkdir(exist_ok=True)

# Limpiar salida anterior
for f in OUTPUT_DIR.iterdir():
    if f.is_file():
        f.unlink()

files = sorted(
    f for f in os.listdir(INPUT_DIR)
    if Path(f).suffix.lower() in {".jpg", ".jpeg", ".png"}
)

if not files:
    print("No hay recortes en cropped_frames/.")
    raise SystemExit(0)

print(f"Evaluando {len(files)} recortes...")

def blur_score(img_gray):
    """Laplacian variance — mayor valor = imagen mas nitida."""
    return cv2.Laplacian(img_gray, cv2.CV_64F).var()

def brightness_ok(img_bgr):
    """Devuelve True si la imagen no esta sobreexpuesta ni muy oscura."""
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    total = gray.size
    overexposed  = np.sum(gray > 245) / total
    underexposed = np.sum(gray < 20)  / total
    return overexposed < MAX_OVEREXPOSED_PCT and underexposed < MAX_UNDEREXPOSED_PCT

candidates = defaultdict(list)   # video → [(score, name, path)]
descartadas = 0

for fname in files:
    fpath = INPUT_DIR / fname

    img = cv2.imread(str(fpath))
    if img is None:
        print(f"  [SKIP] No se pudo leer: {fname}")
        descartadas += 1
        continue

    h, w = img.shape[:2]

    # Filtro 1: tamano minimo
    if w < MIN_WIDTH or h < MIN_HEIGHT:
        print(f"  [SKIP] Muy pequeno ({w}x{h}): {fname}")
        descartadas += 1
        continue

    # Filtro 2: brillo
    if not brightness_ok(img):
        print(f"  [SKIP] Brillo fuera de rango: {fname}")
        descartadas += 1
        continue

    # Nitidez: solo se usa para rankear, no para descartar
    gray  = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    score = blur_score(gray)

    # Agrupar por video (todo lo que va antes de _frame_)
    if "_frame_" in fname:
        video = fname.split("_frame_")[0]
    else:
        video = "sin_nombre"

    candidates[video].append((score, fname, fpath))

# Seleccionar los mejores TOP_N por video
saved = 0
for video, imgs in candidates.items():
    imgs.sort(key=lambda x: x[0], reverse=True)   # mayor nitidez primero
    top = imgs[:TOP_N]

    print(f"\n{video}: {len(imgs)} candidatas → guardando {len(top)}")

    for score, fname, fpath in top:
        shutil.copy2(fpath, OUTPUT_DIR / fname)
        saved += 1
        print(f"  [OK] {fname}  nitidez={score:.1f}")

print("\n===== RESUMEN =====")
print(f"Recortes evaluados : {len(files)}")
print(f"Descartadas        : {descartadas}")
print(f"Videos con pizza   : {len(candidates)}")
print(f"Imagenes guardadas : {saved}")
print(f"Guardadas en       : {OUTPUT_DIR}")
