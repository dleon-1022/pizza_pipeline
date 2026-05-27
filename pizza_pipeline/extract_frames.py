import os
import subprocess

VIDEO_DIR = r"C:\Users\gritseeuser1\Documents\qualityvids"
OUTPUT_DIR = r"C:\pizza_pipeline\frames"
PROCESSED_FILE = r"C:\pizza_pipeline\processed_videos.txt"

VALID_HOURS = {11, 12, 13, 14, 15, 18, 19, 20, 21}

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Limpiar frames anteriores
for f in os.listdir(OUTPUT_DIR):
    fp = os.path.join(OUTPUT_DIR, f)
    if os.path.isfile(fp):
        os.remove(fp)

def get_hour(filename):
    try:
        time_part = filename.split("-")[-1].replace(".mp4", "")
        return int(time_part[:2])
    except Exception:
        return None

def load_processed():
    if not os.path.exists(PROCESSED_FILE):
        return set()

    with open(PROCESSED_FILE, "r", encoding="utf-8") as f:
        return set(line.strip() for line in f if line.strip())

def save_processed(video_name):
    with open(PROCESSED_FILE, "a", encoding="utf-8") as f:
        f.write(video_name + "\n")

processed_videos = load_processed()

videos = []
for v in os.listdir(VIDEO_DIR):
    if not v.lower().endswith(".mp4"):
        continue

    if v in processed_videos:
        continue

    h = get_hour(v)
    if h in VALID_HOURS:
        videos.append(v)

videos.sort()

if not videos:
    print("No hay videos nuevos válidos para procesar.")
    raise SystemExit(0)

processed_ok = 0
processed_error = 0

for video in videos:
    video_path = os.path.join(VIDEO_DIR, video)
    out_pattern = os.path.join(
        OUTPUT_DIR,
        f"{os.path.splitext(video)[0]}_frame_%04d.jpg"
    )

    print(f"Procesando {video}")

    cmd = [
        "ffmpeg",
        "-v", "error",
        "-threads", "1",
        "-i", video_path,
        "-vf", "fps=1/20",
        "-q:v", "2",
        out_pattern
    ]

    result = subprocess.run(cmd)

    if result.returncode != 0:
        processed_error += 1
        print(f"[ERROR] Falló extracción para {video}")
        continue

    processed_ok += 1
    save_processed(video)
    print(f"[OK] Procesado: {video}")

print("\n===== RESUMEN EXTRACCION =====")
print(f"Videos nuevos procesados: {processed_ok}")
print(f"Videos con error: {processed_error}")
print(f"Frames guardados en: {OUTPUT_DIR}")