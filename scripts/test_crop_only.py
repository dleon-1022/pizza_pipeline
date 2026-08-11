"""
=============================================================================
 PRUEBA: SOLO CROP (YOLO) - SIN CLASIFICADOR RESNET
=============================================================================
Objetivo
--------
Medir cuantas imagenes (crops de pizza) se obtendrian si el pipeline corriera
UNICAMENTE el modelo de crop (YOLO) directo sobre TODOS los frames extraidos
del video, sin pasar antes por classify_frames.py (ResNet) ni por el relleno
aleatorio.

Que hace
--------
1. Lee todos los frames de --input_dir (por defecto C:\\pizza_pipeline\\frames).
2. Corre YOLO UNA sola vez por frame con el umbral mas bajo del barrido y
   guarda la confianza de cada deteccion.
3. Con esas confianzas calcula, sin re-inferir, cuantos crops saldrian con
   cada umbral del barrido (--conf_sweep).
4. Guarda los crops PNG del umbral --save_conf (por defecto 0.45, igual que
   produccion) en --output_dir\\crops.
5. Escribe reportes CSV (por frame, por video, por umbral) y un HTML con
   muestra visual: crops guardados + frames donde NO se detecto nada.

NO toca nada de produccion: no borra frames, no escribe en selected_frames ni
en cropped_frames, no sube a S3 ni a Sheets, no marca videos como procesados.

Uso tipico
----------
    python test_crop_only.py

Variantes
---------
    python test_crop_only.py --limit 300            (prueba rapida)
    python test_crop_only.py --save_conf 0.35
    python test_crop_only.py --conf_sweep 0.2 0.3 0.4 0.5 0.6 0.7
    python test_crop_only.py --no_save_crops        (solo conteos)
=============================================================================
"""

import argparse
import base64
import csv
import html
import io
import os
import random
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}

DEFAULT_BASE = Path(r"C:\pizza_pipeline")


# =============================================================================
# ARGUMENTOS
# =============================================================================
def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prueba de solo-crop (YOLO) sobre los frames extraidos, sin clasificador ResNet."
    )
    parser.add_argument(
        "-mod", "--model",
        default=str(DEFAULT_BASE / "models" / "best.pt"),
        help="Ruta al modelo YOLO (.pt). Default: C:\\pizza_pipeline\\models\\best.pt",
    )
    parser.add_argument(
        "-i", "--input_dir",
        default=str(DEFAULT_BASE / "frames"),
        help="Carpeta con los frames extraidos. Default: C:\\pizza_pipeline\\frames",
    )
    parser.add_argument(
        "-o", "--output_dir",
        default=str(DEFAULT_BASE / "test_crop_only"),
        help="Carpeta de salida de la prueba. Default: C:\\pizza_pipeline\\test_crop_only",
    )
    parser.add_argument(
        "--conf_sweep",
        type=float,
        nargs="+",
        default=[0.25, 0.35, 0.45, 0.55, 0.65],
        help="Umbrales de confianza a comparar. Default: 0.25 0.35 0.45 0.55 0.65",
    )
    parser.add_argument(
        "--save_conf",
        type=float,
        default=0.45,
        help="Umbral con el que se guardan los crops en disco. Default: 0.45 (igual que produccion).",
    )
    parser.add_argument(
        "--pizza_class_name",
        default="pizza",
        help="Nombre de la clase a recortar (default: pizza).",
    )
    parser.add_argument(
        "--pizza_class_id",
        type=int,
        default=53,
        help="ID de clase de respaldo si no se encuentra el nombre (COCO pizza = 53).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Procesar solo los primeros N frames (0 = todos). Util para pruebas rapidas.",
    )
    parser.add_argument(
        "--no_save_crops",
        action="store_true",
        help="No escribir los PNG recortados; solo contar y reportar.",
    )
    parser.add_argument(
        "--sample_crops",
        type=int,
        default=60,
        help="Cuantos crops incluir en la muestra visual del HTML. Default: 60",
    )
    parser.add_argument(
        "--sample_misses",
        type=int,
        default=12,
        help="Cuantos frames SIN deteccion incluir en el HTML. Default: 12",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=1,
        help="Hilos de CPU para torch (default 1, igual que produccion).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1234,
        help="Semilla para la muestra visual (reproducible).",
    )
    return parser.parse_args(argv)


# =============================================================================
# LOGICA PURA (testeable sin YOLO)
# =============================================================================
def get_video_name(file_name: str) -> str:
    """Deriva el nombre del video a partir del nombre del frame."""
    if "_frame_" in file_name:
        return file_name.split("_frame_")[0]
    return "sin_nombre_video"


def resolve_pizza_class_id(names, class_name: str, fallback_id: int) -> int:
    """Busca el id de la clase objetivo dentro de model.names."""
    mapping = names if isinstance(names, dict) else {}
    lowered = {str(v).lower(): int(k) for k, v in mapping.items()}

    if class_name.lower() in lowered:
        return lowered[class_name.lower()]

    print(
        f"[ADVERTENCIA] La clase '{class_name}' no esta en el modelo "
        f"({sorted(mapping.values()) if mapping else 'sin nombres'}); "
        f"se usara el id {fallback_id}."
    )
    return fallback_id


def clamp_box(x1, y1, x2, y2, width, height):
    """Recorta la caja a los limites de la imagen. Devuelve None si es invalida."""
    x1 = max(0, min(int(x1), width - 1))
    y1 = max(0, min(int(y1), height - 1))
    x2 = max(1, min(int(x2), width))
    y2 = max(1, min(int(y2), height))

    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def count_by_threshold(confidences, thresholds):
    """Cuantas detecciones pasan cada umbral. confidences: lista de floats."""
    return {t: sum(1 for c in confidences if c >= t) for t in thresholds}


def summarize(per_frame, thresholds):
    """
    Construye los agregados del reporte.
    per_frame: lista de dicts con keys: frame, video, confidences (lista).
    """
    totals = {t: 0 for t in thresholds}
    frames_with_det = {t: 0 for t in thresholds}
    per_video_crops = {t: defaultdict(int) for t in thresholds}
    per_video_frames = defaultdict(int)

    for row in per_frame:
        per_video_frames[row["video"]] += 1
        counts = count_by_threshold(row["confidences"], thresholds)
        row["counts"] = counts

        for t in thresholds:
            totals[t] += counts[t]
            if counts[t] > 0:
                frames_with_det[t] += 1
            per_video_crops[t][row["video"]] += counts[t]

    return {
        "totals": totals,
        "frames_with_det": frames_with_det,
        "per_video_crops": per_video_crops,
        "per_video_frames": per_video_frames,
    }


# =============================================================================
# HTML DE MUESTRA VISUAL
# =============================================================================
def encode_thumb(image_bgr, max_width=260, quality=72):
    """Convierte una imagen BGR (numpy) en un data URI JPEG reducido."""
    import cv2

    if image_bgr is None or getattr(image_bgr, "size", 0) == 0:
        return None

    h, w = image_bgr.shape[:2]
    if w > max_width:
        scale = max_width / float(w)
        image_bgr = cv2.resize(
            image_bgr,
            (max_width, max(1, int(h * scale))),
            interpolation=cv2.INTER_AREA,
        )

    ok, buf = cv2.imencode(".jpg", image_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    if not ok:
        return None
    return "data:image/jpeg;base64," + base64.b64encode(buf.tobytes()).decode("ascii")


def build_html(args, thresholds, per_frame, agg, crop_samples, miss_samples, elapsed_desc):
    """Genera el reporte HTML autocontenido."""
    totals = agg["totals"]
    frames_with_det = agg["frames_with_det"]
    total_frames = len(per_frame)

    sweep_rows = []
    for t in thresholds:
        pct_frames = (frames_with_det[t] / total_frames * 100) if total_frames else 0.0
        avg = (totals[t] / total_frames) if total_frames else 0.0
        marca = " (guardado en disco)" if abs(t - args.save_conf) < 1e-9 else ""
        sweep_rows.append(
            "<tr><td><b>{:.2f}</b>{}</td><td class='num'>{}</td>"
            "<td class='num'>{}</td><td class='num'>{:.1f}%</td>"
            "<td class='num'>{:.2f}</td></tr>".format(
                t, marca, totals[t], frames_with_det[t], pct_frames, avg
            )
        )

    video_rows = []
    for video in sorted(agg["per_video_frames"]):
        cells = "".join(
            "<td class='num'>{}</td>".format(agg["per_video_crops"][t][video])
            for t in thresholds
        )
        video_rows.append(
            "<tr><td>{}</td><td class='num'>{}</td>{}</tr>".format(
                html.escape(video), agg["per_video_frames"][video], cells
            )
        )

    crop_cards = []
    for item in crop_samples:
        crop_cards.append(
            "<figure><img src='{}' alt=''><figcaption>{}<br><span class='conf'>conf {:.3f}</span>"
            "</figcaption></figure>".format(
                item["thumb"], html.escape(item["label"]), item["conf"]
            )
        )

    miss_cards = []
    for item in miss_samples:
        miss_cards.append(
            "<figure><img src='{}' alt=''><figcaption>{}</figcaption></figure>".format(
                item["thumb"], html.escape(item["label"])
            )
        )

    sweep_header = "".join("<th>conf {:.2f}</th>".format(t) for t in thresholds)

    return """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Prueba solo-crop (YOLO) - Pizza Quality</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font-family: -apple-system, "Segoe UI", Roboto, sans-serif; margin: 0;
         padding: 32px; background: #f6f7f9; color: #1c1e21; }}
  @media (prefers-color-scheme: dark) {{
    body {{ background: #16181c; color: #e8eaed; }}
    section, .kpi {{ background: #22252a !important; border-color: #33373d !important; }}
    th {{ background: #2b2f35 !important; }}
    td, th {{ border-color: #33373d !important; }}
  }}
  h1 {{ font-size: 22px; margin: 0 0 4px; }}
  .sub {{ color: #6b7280; font-size: 13px; margin-bottom: 24px; }}
  section {{ background: #fff; border: 1px solid #e3e5e8; border-radius: 10px;
             padding: 20px 24px; margin-bottom: 20px; }}
  h2 {{ font-size: 15px; text-transform: uppercase; letter-spacing: .06em;
        color: #6b7280; margin: 0 0 16px; }}
  .kpis {{ display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }}
  .kpi {{ background: #fff; border: 1px solid #e3e5e8; border-radius: 10px;
          padding: 14px 18px; min-width: 150px; }}
  .kpi .v {{ font-size: 26px; font-weight: 650; }}
  .kpi .l {{ font-size: 12px; color: #6b7280; margin-top: 2px; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
  th, td {{ border-bottom: 1px solid #e8eaed; padding: 7px 10px; text-align: left; }}
  th {{ background: #f2f3f5; font-weight: 600; }}
  td.num, th.num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  .grid {{ display: flex; flex-wrap: wrap; gap: 12px; }}
  figure {{ margin: 0; width: 180px; }}
  figure img {{ width: 100%; border-radius: 6px; display: block; background: #ddd; }}
  figcaption {{ font-size: 10.5px; color: #6b7280; margin-top: 5px;
                word-break: break-all; line-height: 1.35; }}
  .conf {{ color: #1c1e21; font-weight: 600; }}
  @media (prefers-color-scheme: dark) {{ .conf {{ color: #e8eaed; }} }}
  .note {{ font-size: 12.5px; color: #6b7280; margin-top: 12px; line-height: 1.5; }}
</style>
</head>
<body>
<h1>Prueba: solo modelo de crop (YOLO), sin clasificador ResNet</h1>
<div class="sub">Generado {generado} &middot; frames de <code>{input_dir}</code>
 &middot; modelo <code>{model}</code> &middot; {elapsed}</div>

<div class="kpis">
  <div class="kpi"><div class="v">{total_frames}</div><div class="l">Frames analizados</div></div>
  <div class="kpi"><div class="v">{n_videos}</div><div class="l">Videos</div></div>
  <div class="kpi"><div class="v">{crops_save}</div><div class="l">Crops @ conf {save_conf:.2f}</div></div>
  <div class="kpi"><div class="v">{pct_hit:.1f}%</div><div class="l">Frames con &ge;1 pizza @ {save_conf:.2f}</div></div>
</div>

<section>
<h2>Barrido de umbrales</h2>
<table>
<thead><tr><th>conf</th><th class="num">Crops totales</th>
<th class="num">Frames con deteccion</th><th class="num">% frames</th>
<th class="num">Crops por frame</th></tr></thead>
<tbody>
{sweep_rows}
</tbody>
</table>
<div class="note">Una sola inferencia por frame: las columnas se derivan de las confianzas
de cada deteccion, asi que los conteos son exactamente los que daria correr YOLO con ese
<code>--conf</code>. Compara estos totales con lo que produce hoy el pipeline (ResNet
selecciona 100-150 frames y solo esos llegan al crop).</div>
</section>

<section>
<h2>Por video</h2>
<table>
<thead><tr><th>Video</th><th class="num">Frames</th>{sweep_header}</tr></thead>
<tbody>
{video_rows}
</tbody>
</table>
</section>

<section>
<h2>Muestra de crops guardados (conf &ge; {save_conf:.2f})</h2>
<div class="grid">
{crop_cards}
</div>
<div class="note">Muestra aleatoria reproducible (semilla {seed}). Revisa aqui si hay
recortes cortados, duplicados de la misma pizza, o cajas sobre objetos que no son pizza.</div>
</section>

<section>
<h2>Frames SIN ninguna deteccion (conf &ge; {save_conf:.2f})</h2>
<div class="grid">
{miss_cards}
</div>
<div class="note">Si aqui aparecen pizzas visibles, el problema es el umbral o el modelo de
crop, no el clasificador.</div>
</section>

</body>
</html>
""".format(
        generado=datetime.now().strftime("%Y-%m-%d %H:%M"),
        input_dir=html.escape(str(args.input_dir)),
        model=html.escape(str(args.model)),
        elapsed=html.escape(elapsed_desc),
        total_frames=total_frames,
        n_videos=len(agg["per_video_frames"]),
        crops_save=totals.get(args.save_conf, 0),
        save_conf=args.save_conf,
        pct_hit=(frames_with_det.get(args.save_conf, 0) / total_frames * 100) if total_frames else 0.0,
        sweep_rows="\n".join(sweep_rows),
        sweep_header=sweep_header,
        video_rows="\n".join(video_rows) or "<tr><td colspan='9'>sin datos</td></tr>",
        crop_cards="\n".join(crop_cards) or "<p class='note'>Sin crops en este umbral.</p>",
        miss_cards="\n".join(miss_cards) or "<p class='note'>Todos los frames tuvieron al menos una deteccion.</p>",
        seed=args.seed,
    )


# =============================================================================
# CSV
# =============================================================================
def write_csvs(output_dir: Path, thresholds, per_frame, agg):
    frames_csv = output_dir / "reporte_por_frame.csv"
    with open(frames_csv, "w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(
            ["video", "frame", "detecciones_totales", "conf_max", "conf_min"]
            + ["crops_conf_{:.2f}".format(t) for t in thresholds]
            + ["confianzas"]
        )
        for row in per_frame:
            confs = row["confidences"]
            writer.writerow(
                [
                    row["video"],
                    row["frame"],
                    len(confs),
                    "{:.4f}".format(max(confs)) if confs else "",
                    "{:.4f}".format(min(confs)) if confs else "",
                ]
                + [row["counts"][t] for t in thresholds]
                + ["|".join("{:.4f}".format(c) for c in confs)]
            )

    videos_csv = output_dir / "reporte_por_video.csv"
    with open(videos_csv, "w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(
            ["video", "frames"] + ["crops_conf_{:.2f}".format(t) for t in thresholds]
        )
        for video in sorted(agg["per_video_frames"]):
            writer.writerow(
                [video, agg["per_video_frames"][video]]
                + [agg["per_video_crops"][t][video] for t in thresholds]
            )

    sweep_csv = output_dir / "reporte_umbrales.csv"
    total_frames = len(per_frame)
    with open(sweep_csv, "w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(
            ["conf", "crops_totales", "frames_con_deteccion", "pct_frames", "crops_por_frame"]
        )
        for t in thresholds:
            writer.writerow(
                [
                    "{:.2f}".format(t),
                    agg["totals"][t],
                    agg["frames_with_det"][t],
                    "{:.2f}".format(agg["frames_with_det"][t] / total_frames * 100) if total_frames else "0.00",
                    "{:.3f}".format(agg["totals"][t] / total_frames) if total_frames else "0.000",
                ]
            )

    return frames_csv, videos_csv, sweep_csv


# =============================================================================
# PRINCIPAL
# =============================================================================
def iter_images(input_dir: Path):
    for path in sorted(input_dir.iterdir()):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def main(argv=None) -> int:
    args = parse_args(argv)

    import cv2  # noqa: F401  (se usa en encode_thumb / imwrite)

    try:
        import torch

        torch.set_num_threads(max(1, args.threads))
        try:
            torch.set_num_interop_threads(max(1, args.threads))
        except RuntimeError:
            pass  # ya inicializado; no es critico
    except ImportError:
        print("[ADVERTENCIA] torch no disponible; se omite el limite de hilos.")

    from ultralytics import YOLO

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    crops_dir = output_dir / "crops"

    if not input_dir.is_dir():
        print(f"[ERROR] No existe la carpeta de frames: {input_dir}")
        return 1

    model_path = Path(args.model)
    if not model_path.is_file():
        print(f"[ERROR] No existe el modelo: {model_path}")
        return 1

    thresholds = sorted(set(round(float(t), 6) for t in args.conf_sweep))
    args.save_conf = round(float(args.save_conf), 6)
    if args.save_conf not in thresholds:
        thresholds.append(args.save_conf)
        thresholds.sort()

    min_conf = min(thresholds)

    output_dir.mkdir(parents=True, exist_ok=True)
    if not args.no_save_crops:
        crops_dir.mkdir(parents=True, exist_ok=True)
        # Limpiar crops de corridas anteriores de ESTA prueba (no toca produccion)
        for old in crops_dir.glob("*.png"):
            try:
                old.unlink()
            except OSError as exc:
                print(f"[ADVERTENCIA] No se pudo borrar {old.name}: {exc}")

    frames = list(iter_images(input_dir))
    if args.limit and args.limit > 0:
        frames = frames[: args.limit]

    if not frames:
        print(f"[ERROR] No hay imagenes en {input_dir}")
        return 1

    print("=" * 62)
    print(" PRUEBA SOLO-CROP (YOLO) - SIN CLASIFICADOR RESNET")
    print("=" * 62)
    print(f"Frames a analizar : {len(frames)}")
    print(f"Modelo            : {model_path}")
    print(f"Umbrales          : {', '.join('{:.2f}'.format(t) for t in thresholds)}")
    print(f"Inferencia a conf : {min_conf:.2f} (una pasada, se filtra despues)")
    print(f"Guardando crops   : {'NO' if args.no_save_crops else 'si, conf >= {:.2f}'.format(args.save_conf)}")
    print(f"Salida            : {output_dir}")
    print("-" * 62)

    model = YOLO(str(model_path))
    pizza_class_id = resolve_pizza_class_id(
        model.names, args.pizza_class_name, args.pizza_class_id
    )

    started = datetime.now()

    per_frame = []
    crop_pool = []   # (label, conf, ruta_o_None, frame_path, box)
    miss_pool = []   # frames sin deteccion al umbral save_conf
    total_saved = 0
    read_errors = 0

    for index, frame_path in enumerate(frames, start=1):
        try:
            results = model.predict(
                source=str(frame_path), conf=min_conf, verbose=False
            )
        except Exception as exc:
            read_errors += 1
            print(f"[ERROR] Fallo la inferencia en {frame_path.name}: {exc}")
            continue

        if not results:
            read_errors += 1
            print(f"[ERROR] Sin resultado para {frame_path.name}")
            continue

        result = results[0]
        image = result.orig_img
        height, width = image.shape[:2]

        detections = []  # (conf, box)
        for box in result.boxes:
            if int(box.cls.item()) != pizza_class_id:
                continue

            clamped = clamp_box(*box.xyxy[0].tolist(), width=width, height=height)
            if clamped is None:
                continue

            detections.append((float(box.conf.item()), clamped))

        # Mismo orden que produccion: arriba-izquierda primero
        detections.sort(key=lambda d: (d[1][1], d[1][0]))

        confidences = [c for c, _ in detections]
        per_frame.append(
            {
                "frame": frame_path.name,
                "video": get_video_name(frame_path.name),
                "confidences": confidences,
            }
        )

        # Guardar crops del umbral objetivo
        kept = [(c, b) for c, b in detections if c >= args.save_conf]

        if not kept:
            miss_pool.append(frame_path)

        for idx, (conf, (x1, y1, x2, y2)) in enumerate(kept, start=1):
            crop = image[y1:y2, x1:x2]
            if crop.size == 0:
                continue

            label = f"{frame_path.stem}_{idx}.png"
            saved_path = None

            if not args.no_save_crops:
                saved_path = crops_dir / label
                if cv2.imwrite(str(saved_path), crop):
                    total_saved += 1
                else:
                    print(f"[ADVERTENCIA] No se pudo escribir {label}")
                    saved_path = None

            crop_pool.append(
                {
                    "label": label,
                    "conf": conf,
                    "frame_path": frame_path,
                    "box": (x1, y1, x2, y2),
                }
            )

        if index % 100 == 0 or index == len(frames):
            print(f"[INFO] {index}/{len(frames)} frames | crops acumulados: {len(crop_pool)}")

    if not per_frame:
        print("[ERROR] Ningun frame pudo procesarse.")
        return 1

    agg = summarize(per_frame, thresholds)

    # -------------------------------------------------------------------------
    # Muestra visual
    # -------------------------------------------------------------------------
    rng = random.Random(args.seed)

    crop_sample_items = []
    if crop_pool and args.sample_crops > 0:
        chosen = rng.sample(crop_pool, min(args.sample_crops, len(crop_pool)))
        chosen.sort(key=lambda c: c["conf"], reverse=True)
        for item in chosen:
            image = cv2.imread(str(item["frame_path"]))
            if image is None:
                continue
            x1, y1, x2, y2 = item["box"]
            thumb = encode_thumb(image[y1:y2, x1:x2])
            if thumb:
                crop_sample_items.append(
                    {"thumb": thumb, "label": item["label"], "conf": item["conf"]}
                )

    miss_sample_items = []
    if miss_pool and args.sample_misses > 0:
        chosen = rng.sample(miss_pool, min(args.sample_misses, len(miss_pool)))
        for frame_path in chosen:
            image = cv2.imread(str(frame_path))
            if image is None:
                continue
            thumb = encode_thumb(image, max_width=320)
            if thumb:
                miss_sample_items.append({"thumb": thumb, "label": frame_path.name})

    elapsed = datetime.now() - started
    elapsed_desc = "{:.1f} min de inferencia".format(elapsed.total_seconds() / 60.0)

    # -------------------------------------------------------------------------
    # Reportes
    # -------------------------------------------------------------------------
    frames_csv, videos_csv, sweep_csv = write_csvs(output_dir, thresholds, per_frame, agg)

    html_path = output_dir / "reporte_solo_crop.html"
    html_path.write_text(
        build_html(
            args, thresholds, per_frame, agg,
            crop_sample_items, miss_sample_items, elapsed_desc,
        ),
        encoding="utf-8",
    )

    # -------------------------------------------------------------------------
    # Resumen en consola
    # -------------------------------------------------------------------------
    total_frames = len(per_frame)
    print("\n" + "=" * 62)
    print(" RESULTADOS: CROPS SEGUN UMBRAL")
    print("=" * 62)
    print("{:>6}  {:>12}  {:>18}  {:>10}".format("conf", "crops", "frames con det.", "% frames"))
    for t in thresholds:
        marca = "  <-- guardado" if abs(t - args.save_conf) < 1e-9 else ""
        print(
            "{:>6.2f}  {:>12}  {:>18}  {:>9.1f}%{}".format(
                t,
                agg["totals"][t],
                agg["frames_with_det"][t],
                (agg["frames_with_det"][t] / total_frames * 100) if total_frames else 0.0,
                marca,
            )
        )

    print("\n===== RESUMEN =====")
    print(f"Frames analizados        : {total_frames}")
    print(f"Videos distintos         : {len(agg['per_video_frames'])}")
    print(f"Frames con error         : {read_errors}")
    print(f"Crops @ conf {args.save_conf:.2f}      : {agg['totals'][args.save_conf]}")
    print(f"Crops escritos en disco  : {total_saved}")
    print(f"Frames sin deteccion     : {len(miss_pool)}")
    print(f"\nCSV por frame  : {frames_csv}")
    print(f"CSV por video  : {videos_csv}")
    print(f"CSV umbrales   : {sweep_csv}")
    print(f"HTML visual    : {html_path}")
    if not args.no_save_crops:
        print(f"Crops PNG      : {crops_dir}")
    print("\nNota: esta prueba NO modifico frames/, selected_frames/ ni cropped_frames/,")
    print("      ni subio nada a S3/Sheets, ni marco videos como procesados.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
