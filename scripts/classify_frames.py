import os
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

OUTPUT_DIR.mkdir(exist_ok=True)

# Limpiar salida anterior
for f in OUTPUT_DIR.iterdir():
    if f.is_file():
        f.unlink()

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

files = sorted(
    f for f in os.listdir(INPUT_DIR)
    if f.lower().endswith((".jpg", ".jpeg", ".png"))
)

if not files:
    print("No hay frames para clasificar.")
    raise SystemExit(0)

candidates = defaultdict(list)

batch_tensors = []
batch_names = []
batch_paths = []

def process_batch():
    global batch_tensors, batch_names, batch_paths

    if not batch_tensors:
        return

    batch = torch.stack(batch_tensors)

    with torch.no_grad():
        outputs = model(batch)
        probs = torch.softmax(outputs, dim=1)

    for i in range(len(batch_names)):
        pred = outputs[i].argmax().item()
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

saved = 0

for video, imgs in candidates.items():
    imgs.sort(key=lambda x: x[0], reverse=True)
    top = imgs[:6]

    print(f"\n{video}: {len(imgs)} candidatas, guardando {len(top)}")

    for score, name, path in top:
        shutil.copy2(path, OUTPUT_DIR / name)
        saved += 1
        print(f"[OK] {name} | prob_buena={score:.3f}")

print("\n===== RESUMEN =====")
print(f"Videos con candidatas: {len(candidates)}")
print(f"Total imágenes guardadas: {saved}")
print(f"Guardadas en: {OUTPUT_DIR}")