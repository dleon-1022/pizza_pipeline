import os
import random
import shutil
from pathlib import Path
from collections import defaultdict

import torch
from torch import nn
from torchvision import transforms, models
from PIL import Image

# Limitar uso de CPU en PyTorch
torch.set_num_threads(1)
torch.set_num_interop_threads(1)

BASE_DIR = Path(r"C:\pizza_pipeline")
MODEL_PATH = BASE_DIR / "models" / "frame_classifier.pth"
INPUT_DIR = BASE_DIR / "frames"        # frames completos, como fue entrenado el modelo
OUTPUT_DIR = BASE_DIR / "selected_frames"

BATCH_SIZE = 16

# Si la clasificacion falla o no selecciona ninguna imagen buena, se copia
# una cantidad aleatoria de frames (entre estos limites) como respaldo,
# para asegurar que siempre haya imagenes para recortar y subir.
FALLBACK_MIN = 5
FALLBACK_MAX = 15

OUTPUT_DIR.mkdir(exist_ok=True)

# Limpiar salida anterior
for f in OUTPUT_DIR.iterdir():
    if f.is_file():
        f.unlink()

files = sorted(
    f for f in os.listdir(INPUT_DIR)
    if f.lower().endswith((".jpg", ".jpeg", ".png"))
)

if not files:
    print("No hay frames para clasificar.")
    raise SystemExit(0)

candidates = defaultdict(list)


def run_classification() -> int:
    """Corre el modelo ResNet y guarda hasta 6 frames buenos por video en
    OUTPUT_DIR. Devuelve la cantidad de imagenes guardadas."""

    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"No existe el modelo entrenado: {MODEL_PATH}")

    checkpoint = torch.load(MODEL_PATH, map_location="cpu")
    classes = checkpoint["classes"]
    img_size = checkpoint["img_size"]

    if "buenas" not in classes:
        raise ValueError("No se encontró la clase 'buenas' en el modelo")

    good_idx = classes.index("buenas")

    model = models.resnet18(weights=None)
    model.fc = nn.Linear(model.fc.in_features, len(classes))
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    tfms = transforms.Compose([
        transforms.Resize((img_size, img_size)),
        transforms.ToTensor(),
    ])

    batch_tensors = []
    batch_names = []
    batch_paths = []

    def process_batch():
        nonlocal batch_tensors, batch_names, batch_paths

        if not batch_tensors:
            return

        batch = torch.stack(batch_tensors)

        with torch.no_grad():
            outputs = model(batch)
            probs = torch.softmax(outputs, dim=1)

        for i in range(len(batch_names)):
            score = probs[i, good_idx].item()

            if score > 0.3:
                name = batch_names[i]
                path = batch_paths[i]

                if "_frame_" in name:
                    video = name.split("_frame_")[0]
                else:
                    video = "sin_nombre_video"

                candidates[video].append((score, name, path))

        batch_tensors = []
        batch_names = []
        batch_paths = []

    for f in files:
        path = INPUT_DIR / f

        try:
            img = Image.open(path).convert("RGB")
        except Exception as e:
            print(f"[ERROR] No se pudo abrir {f}: {e}")
            continue

        tensor = tfms(img)
        batch_tensors.append(tensor)
        batch_names.append(f)
        batch_paths.append(path)

        if len(batch_tensors) == BATCH_SIZE:
            process_batch()

    process_batch()

    saved_count = 0

    for video, imgs in candidates.items():
        imgs.sort(key=lambda x: x[0], reverse=True)
        top = imgs[:6]

        print(f"\n{video}: {len(imgs)} candidatas, guardando {len(top)}")

        for score, name, path in top:
            shutil.copy2(path, OUTPUT_DIR / name)
            saved_count += 1
            print(f"[OK] {name} | prob_buena={score:.3f}")

    return saved_count


def apply_random_fallback() -> int:
    """Copia una cantidad aleatoria de frames (sin clasificar) a OUTPUT_DIR.
    Se usa cuando la clasificacion falla o no arroja ninguna imagen buena,
    para garantizar que el pipeline siempre tenga imagenes que recortar y
    subir."""

    if not files:
        print("[FALLBACK] No hay frames disponibles para el respaldo aleatorio.")
        return 0

    lower = min(FALLBACK_MIN, len(files))
    upper = min(FALLBACK_MAX, len(files))
    n_fallback = random.randint(lower, upper)
    fallback_selected = random.sample(files, n_fallback)

    fallback_saved = 0
    for name in fallback_selected:
        shutil.copy2(INPUT_DIR / name, OUTPUT_DIR / name)
        fallback_saved += 1
        print(f"[FALLBACK] {name}")

    print(f"[FALLBACK] {fallback_saved} imagenes aleatorias copiadas a {OUTPUT_DIR}")
    return fallback_saved


try:
    saved = run_classification()
except Exception as e:
    print(f"[ERROR] Fallo la clasificacion ResNet: {e}")
    saved = 0

# =====================================================
# Respaldo: si la clasificacion no selecciono ninguna
# imagen (por fallo del modelo o porque ningun frame
# supero el umbral), se toma una cantidad aleatoria de
# frames para asegurar que siempre haya imagenes para
# recortar y subir.
# =====================================================
if saved == 0:
    print("\n[FALLBACK] No se selecciono ninguna imagen buena. Aplicando seleccion aleatoria de respaldo...")
    saved = apply_random_fallback()

print("\n===== RESUMEN =====")
print(f"Videos con candidatas: {len(candidates)}")
print(f"Total imágenes guardadas: {saved}")
print(f"Guardadas en: {OUTPUT_DIR}")
