import os
import random
import shutil
from pathlib import Path
from collections import defaultdict

import torch
from torch import nn
from torchvision import transforms, models
from PIL import Image

# =====================================================
# CONFIGURACIÓN GENERAL
# =====================================================
# Limitar el uso de CPU en PyTorch
torch.set_num_threads(1)
torch.set_num_interop_threads(1)

BASE_DIR = Path(r"C:\pizza_pipeline")
MODEL_PATH = BASE_DIR / "models" / "frame_classifier.pth"
INPUT_DIR = BASE_DIR / "frames"
OUTPUT_DIR = BASE_DIR / "selected_frames"

BATCH_SIZE = 16

# Probabilidad mínima para considerar una imagen como buena
GOOD_THRESHOLD = 0.30

# Máximo de imágenes clasificadas que se guardan por video
MAX_GOOD_PER_VIDEO = 30

# Cantidad total final que se desea obtener
TARGET_MIN = 100
TARGET_MAX = 150
# Si quieres siempre exactamente 150 imágenes, cambia a:
# TARGET_MIN = 150
# TARGET_MAX = 150

# Si la proporción de imágenes realmente clasificadas como "buenas"
# (frente al total final, que incluye el relleno aleatorio) cae por
# debajo de este umbral, se imprime una advertencia. Esto ayuda a
# detectar a tiempo problemas con el modelo o con los frames de
# entrada, ya que el relleno aleatorio siempre completa hasta
# TARGET_MIN/TARGET_MAX y podría ocultar una clasificación que
# esté fallando.
MIN_GOOD_RATIO_WARNING = 0.5

# =====================================================
# PREPARAR CARPETAS
# =====================================================
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

if not INPUT_DIR.exists():
    print(f"[ERROR] No existe la carpeta de entrada: {INPUT_DIR}")
    raise SystemExit(1)

# Limpiar completamente la salida anterior
for item in OUTPUT_DIR.iterdir():
    try:
        if item.is_file() or item.is_symlink():
            item.unlink()
        elif item.is_dir():
            shutil.rmtree(item)
    except Exception as e:
        print(f"[ADVERTENCIA] No se pudo eliminar {item}: {e}")

# =====================================================
# OBTENER IMÁGENES DE ENTRADA
# =====================================================
files = sorted(
    file_name
    for file_name in os.listdir(INPUT_DIR)
    if file_name.lower().endswith((".jpg", ".jpeg", ".png"))
)

if not files:
    print(f"[ERROR] No hay frames para clasificar en: {INPUT_DIR}")
    raise SystemExit(0)

print(f"[INFO] Frames encontrados: {len(files)}")

if len(files) < TARGET_MIN:
    print(
        f"[ADVERTENCIA] Solo existen {len(files)} imágenes disponibles. "
        f"No será posible obtener al menos {TARGET_MIN} imágenes diferentes."
    )

# Almacena las candidatas agrupadas por nombre de video
candidates = defaultdict(list)


# =====================================================
# FUNCIONES AUXILIARES
# =====================================================
def get_video_name(file_name: str) -> str:
    """
    Obtiene el nombre del video a partir del nombre del frame.
    Ejemplo:
        video_001_frame_000123.jpg
        devuelve:
        video_001
    """
    if "_frame_" in file_name:
        return file_name.split("_frame_")[0]
    return "sin_nombre_video"


def safe_copy(source_path: Path, destination_path: Path) -> bool:
    """
    Copia una imagen de forma segura.
    Devuelve True si fue copiada correctamente.
    """
    try:
        shutil.copy2(source_path, destination_path)
        return True
    except Exception as e:
        print(f"[ERROR] No se pudo copiar {source_path.name}: {e}")
        return False


# =====================================================
# CLASIFICACIÓN CON RESNET
# =====================================================
def run_classification() -> int:
    """
    Ejecuta el modelo ResNet.
    Selecciona imágenes cuya probabilidad para la clase 'buenas'
    sea superior a GOOD_THRESHOLD.
    Luego guarda hasta MAX_GOOD_PER_VIDEO imágenes por video.
    Devuelve la cantidad total de imágenes guardadas.
    """
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"No existe el modelo entrenado: {MODEL_PATH}"
        )

    print(f"[INFO] Cargando modelo: {MODEL_PATH}")
    checkpoint = torch.load(
        MODEL_PATH,
        map_location="cpu"
    )

    required_keys = {
        "classes",
        "img_size",
        "model_state_dict"
    }
    missing_keys = required_keys.difference(checkpoint.keys())
    if missing_keys:
        raise KeyError(
            f"El checkpoint no contiene las claves necesarias: "
            f"{sorted(missing_keys)}"
        )

    classes = checkpoint["classes"]
    img_size = checkpoint["img_size"]

    if "buenas" not in classes:
        raise ValueError(
            "No se encontró la clase 'buenas' en el modelo. "
            f"Clases disponibles: {classes}"
        )

    good_idx = classes.index("buenas")

    model = models.resnet18(weights=None)
    model.fc = nn.Linear(
        model.fc.in_features,
        len(classes)
    )
    model.load_state_dict(
        checkpoint["model_state_dict"]
    )
    model.eval()

    tfms = transforms.Compose([
        transforms.Resize((img_size, img_size)),
        transforms.ToTensor(),
    ])

    batch_tensors = []
    batch_names = []
    batch_paths = []

    def process_batch():
        """
        Procesa el lote actual y agrega las imágenes aprobadas
        al diccionario candidates.
        """
        nonlocal batch_tensors
        nonlocal batch_names
        nonlocal batch_paths

        if not batch_tensors:
            return

        batch = torch.stack(batch_tensors)

        with torch.no_grad():
            outputs = model(batch)
            probabilities = torch.softmax(outputs, dim=1)

        for index in range(len(batch_names)):
            score = probabilities[index, good_idx].item()
            if score >= GOOD_THRESHOLD:
                name = batch_names[index]
                path = batch_paths[index]
                video_name = get_video_name(name)
                candidates[video_name].append(
                    (score, name, path)
                )

        batch_tensors = []
        batch_names = []
        batch_paths = []

    print("[INFO] Iniciando clasificación...")
    for current_index, file_name in enumerate(files, start=1):
        image_path = INPUT_DIR / file_name

        try:
            with Image.open(image_path) as image:
                rgb_image = image.convert("RGB")
                tensor = tfms(rgb_image)
        except Exception as e:
            print(
                f"[ERROR] No se pudo abrir {file_name}: {e}"
            )
            continue

        batch_tensors.append(tensor)
        batch_names.append(file_name)
        batch_paths.append(image_path)

        if len(batch_tensors) >= BATCH_SIZE:
            process_batch()

        if current_index % 100 == 0:
            print(
                f"[INFO] Procesadas {current_index}/{len(files)} imágenes"
            )

    # Procesar el último lote si quedó incompleto
    process_batch()

    saved_count = 0
    print("\n===== RESULTADOS DE CLASIFICACIÓN =====")
    for video_name, images in candidates.items():
        # Ordenar desde la probabilidad más alta
        images.sort(
            key=lambda item: item[0],
            reverse=True
        )
        selected_images = images[:MAX_GOOD_PER_VIDEO]

        print(
            f"\n[VIDEO] {video_name}: "
            f"{len(images)} candidatas, "
            f"guardando {len(selected_images)}"
        )

        for score, file_name, image_path in selected_images:
            destination = OUTPUT_DIR / file_name
            if destination.exists():
                continue

            copied = safe_copy(
                image_path,
                destination
            )
            if copied:
                saved_count += 1
                print(
                    f"[BUENA] {file_name} | "
                    f"probabilidad={score:.3f}"
                )

    return saved_count


# =====================================================
# COMPLETAR CON IMÁGENES ALEATORIAS
# =====================================================
def complete_with_random_frames(current_saved: int) -> int:
    """
    Completa la carpeta OUTPUT_DIR con imágenes aleatorias hasta
    alcanzar una cantidad total elegida entre TARGET_MIN y TARGET_MAX.
    No copia imágenes duplicadas.
    """
    maximum_possible = min(
        TARGET_MAX,
        len(files)
    )
    minimum_possible = min(
        TARGET_MIN,
        maximum_possible
    )

    if maximum_possible <= 0:
        print("[RANDOM] No hay imágenes disponibles.")
        return current_saved

    target = random.randint(
        minimum_possible,
        maximum_possible
    )

    print("\n===== SELECCIÓN ALEATORIA =====")
    print(f"[RANDOM] Objetivo total: {target}")
    print(f"[RANDOM] Ya guardadas: {current_saved}")

    if current_saved >= target:
        print(
            "[RANDOM] La clasificación ya alcanzó "
            "la cantidad objetivo."
        )
        return current_saved

    already_selected = {
        item.name
        for item in OUTPUT_DIR.iterdir()
        if item.is_file()
    }

    available_files = [
        file_name
        for file_name in files
        if file_name not in already_selected
    ]

    needed = target - current_saved
    amount_to_select = min(
        needed,
        len(available_files)
    )

    if amount_to_select <= 0:
        print(
            "[RANDOM] No hay más imágenes disponibles "
            "para completar la selección."
        )
        return current_saved

    random_selected = random.sample(
        available_files,
        amount_to_select
    )

    random_saved = 0
    for file_name in random_selected:
        source = INPUT_DIR / file_name
        destination = OUTPUT_DIR / file_name

        copied = safe_copy(
            source,
            destination
        )
        if copied:
            random_saved += 1
            print(f"[RANDOM] {file_name}")

    final_total = current_saved + random_saved

    print(
        f"\n[RANDOM] Imágenes aleatorias agregadas: "
        f"{random_saved}"
    )
    print(
        f"[RANDOM] Total después de completar: "
        f"{final_total}"
    )

    if final_total < target:
        print(
            f"[ADVERTENCIA] No fue posible alcanzar "
            f"el objetivo de {target} imágenes."
        )

    return final_total


# =====================================================
# EJECUCIÓN PRINCIPAL
# =====================================================
try:
    classified_good = run_classification()
except Exception as e:
    print(
        f"\n[ERROR] Falló la clasificación ResNet: {e}"
    )
    print(
        "[INFO] Se continuará utilizando únicamente "
        "la selección aleatoria."
    )
    classified_good = 0

# Siempre completar hasta obtener entre 100 y 150 imágenes.
# Esto se ejecuta aunque el modelo ya haya encontrado algunas imágenes.
saved = complete_with_random_frames(classified_good)

# =====================================================
# AVISO: proporción de imágenes realmente clasificadas
# =====================================================
# El relleno aleatorio siempre completa hasta TARGET_MIN/TARGET_MAX,
# así que una falla del modelo o pocos frames "buenos" no se nota en
# el conteo total. Este aviso hace explícito cuánto del resultado
# final vino de la clasificación real vs. relleno aleatorio.
good_ratio = (classified_good / saved) if saved > 0 else 0.0
print(
    f"\n[INFO] Imágenes provenientes de la clasificación real: "
    f"{classified_good}/{saved} ({good_ratio:.0%})"
)
if good_ratio < MIN_GOOD_RATIO_WARNING:
    print(
        f"[ADVERTENCIA] Solo el {good_ratio:.0%} de las imágenes finales "
        f"provienen de la clasificación ResNet (umbral: "
        f"{MIN_GOOD_RATIO_WARNING:.0%}). El resto es relleno aleatorio "
        f"sin pasar por el modelo. Revisa el modelo, el umbral "
        f"GOOD_THRESHOLD o la calidad de los frames de entrada."
    )

# =====================================================
# RESUMEN
# =====================================================
print("\n===== RESUMEN FINAL =====")
print(f"Frames disponibles: {len(files)}")
print(f"Videos con candidatas: {len(candidates)}")
print(f"Imágenes clasificadas como buenas: {classified_good}")
print(f"Total de imágenes guardadas: {saved}")
print(f"Carpeta de salida: {OUTPUT_DIR}")
