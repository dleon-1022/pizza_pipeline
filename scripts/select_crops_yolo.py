"""
=============================================================================
 PRODUCCION: SELECCION DE CROPS CON YOLO (sin clasificador ResNet)
=============================================================================
Reemplaza los pasos 2 y 3 del pipeline:
    classify_frames.py (ResNet + relleno aleatorio)  ->  ELIMINADO
    crop_pizza_images.py (crop de los frames buenos) ->  ABSORBIDO AQUI

Flujo
-----
1. Lee TODOS los frames de frames/.
2. Corre YOLO (best.pt) sobre cada frame y guarda cada deteccion de pizza
   con su confianza.
3. Elimina casi-duplicados: si dos frames cercanos del MISMO video tienen una
   caja en practicamente la misma posicion (IoU alto), se queda solo la de
   mayor confianza. Evita subir 6 fotos de la misma pizza en el mostrador.
4. Selecciona las mejores por confianza, repartiendo por turnos entre videos
   para no llenar el dia con una sola camara/hora.
5. Escribe:
     - cropped_frames/  ->  los crops PNG  (lo que sube a S3)
     - selected_frames/ ->  los frames completos de origen de esos crops
   Mismos nombres y mismo formato que crop_pizza_images.py, asi que los pasos
   de S3 y Google Sheets NO cambian.
6. Registra cada corrida en historial_selecciones.csv para monitoreo diario.

Diferencia clave con el flujo viejo
-----------------------------------
Antes: ResNet elegia frames -> si fallaba, el relleno aleatorio completaba
hasta 100-150 con frames NO revisados por ningun modelo, y el conteo final
se veia igual de bien. Ahora el criterio de seleccion es la confianza del
mismo YOLO que hace el crop, y no hay relleno: si no hay suficientes pizzas
detectadas, se sube menos y se avisa.

Uso
---
    python scripts\\select_crops_yolo.py

    python scripts\\select_crops_yolo.py --conf 0.45 --target_min 100 --target_max 150
    python scripts\\select_crops_yolo.py --dry_run          (no escribe nada)
    python scripts\\select_crops_yolo.py --report_html      (reporte visual QA)
=============================================================================
"""

import argparse
import base64
import csv
import html
import re
import shutil
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}

DEFAULT_BASE = Path(r"C:\pizza_pipeline")

FRAME_INDEX_RE = re.compile(r"_frame_(\d+)", re.IGNORECASE)


# =============================================================================
# ARGUMENTOS
# =============================================================================
def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Croppea con YOLO y selecciona las mejores imagenes del dia (reemplaza ResNet)."
    )
    p.add_argument("-mod", "--model", default=str(DEFAULT_BASE / "models" / "best.pt"),
                   help="Modelo YOLO. Default: C:\\pizza_pipeline\\models\\best.pt")
    p.add_argument("-i", "--input_dir", default=str(DEFAULT_BASE / "frames"),
                   help="Frames extraidos. Default: C:\\pizza_pipeline\\frames")
    p.add_argument("-o", "--output_dir", default=str(DEFAULT_BASE / "cropped_frames"),
                   help="Salida de los crops (lo que sube a S3). Default: cropped_frames")
    p.add_argument("--selected_dir", default=str(DEFAULT_BASE / "selected_frames"),
                   help="Salida de los frames completos de origen. Default: selected_frames")
    p.add_argument("--base_dir", default=str(DEFAULT_BASE),
                   help="Carpeta base, donde se guarda el historial. Default: C:\\pizza_pipeline")

    p.add_argument("--conf", type=float, default=0.25,
                   help=("Confianza minima de deteccion. Default: 0.25, calibrado con el barrido "
                         "del 2026-08-10 en Pablo Livas y Diaz Ordaz. El 0.45 del pipeline viejo "
                         "descartaba ~90%% de lo que el modelo si detectaba."))
    p.add_argument("--target_min", type=int, default=40,
                   help="Minimo de imagenes a subir por corrida. Default: 40")
    p.add_argument("--target_max", type=int, default=60,
                   help="Maximo de imagenes a subir por corrida. Default: 60")
    p.add_argument("--max_per_video", type=int, default=30,
                   help="Tope de crops por video, como el MAX_GOOD_PER_VIDEO viejo. 0 = sin tope. Default: 30")

    p.add_argument("--dedup_iou", type=float, default=0.60,
                   help="IoU a partir del cual dos cajas se consideran la misma pizza. 0 = sin dedup. Default: 0.60")
    p.add_argument("--dedup_window", type=int, default=3,
                   help="Cuantos frames hacia atras se compara para el dedup (3 frames = 60 s). Default: 3")

    p.add_argument("--pizza_class_name", default="pizza", help="Clase a recortar. Default: pizza")
    p.add_argument("--pizza_class_id", type=int, default=53,
                   help="ID de respaldo si no se encuentra el nombre (COCO pizza = 53).")

    p.add_argument("--no_clean", action="store_true",
                   help="No limpiar las carpetas de salida antes de escribir.")
    p.add_argument("--no_selected_frames", action="store_true",
                   help="No copiar los frames completos a selected_frames.")
    p.add_argument("--dry_run", action="store_true",
                   help="Calcula y reporta pero no escribe imagenes ni historial.")
    p.add_argument("--report_html", action="store_true",
                   help="Genera reporte_seleccion.html con muestra visual para QA.")
    p.add_argument("--threads", type=int, default=1,
                   help="Hilos de CPU para torch. Default: 1")
    p.add_argument("--fail_under", type=int, default=0,
                   help="Si se seleccionan menos de N imagenes, terminar con codigo de error. 0 = nunca falla.")
    return p.parse_args(argv)


# =============================================================================
# LOGICA PURA (testeable sin YOLO)
# =============================================================================
def get_video_name(file_name: str) -> str:
    if "_frame_" in file_name:
        return file_name.split("_frame_")[0]
    return "sin_nombre_video"


def get_frame_index(file_name: str) -> int:
    """Numero de frame dentro del video. -1 si no se puede leer."""
    match = FRAME_INDEX_RE.search(file_name)
    if not match:
        return -1
    try:
        return int(match.group(1))
    except ValueError:
        return -1


def resolve_pizza_class_id(names, class_name: str, fallback_id: int) -> int:
    mapping = names if isinstance(names, dict) else {}
    lowered = {str(v).lower(): int(k) for k, v in mapping.items()}
    if class_name.lower() in lowered:
        return lowered[class_name.lower()]
    print(f"[ADVERTENCIA] Clase '{class_name}' no esta en el modelo; se usa el id {fallback_id}.")
    return fallback_id


def clamp_box(x1, y1, x2, y2, width, height):
    x1 = max(0, min(int(x1), width - 1))
    y1 = max(0, min(int(y1), height - 1))
    x2 = max(1, min(int(x2), width))
    y2 = max(1, min(int(y2), height))
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def iou(box_a, box_b) -> float:
    """Interseccion sobre union de dos cajas (x1, y1, x2, y2)."""
    ax1, ay1, ax2, ay2 = box_a
    bx1, by1, bx2, by2 = box_b

    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)

    iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
    inter = iw * ih
    if inter == 0:
        return 0.0

    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def dedup_candidates(candidates, iou_threshold: float, window: int):
    """
    Elimina casi-duplicados de la MISMA pizza en frames cercanos del mismo video.

    candidates: lista de dicts con keys frame, video, frame_index, conf, box.
    Devuelve (conservados, descartados).

    Regla: recorriendo los frames en orden, si una caja se parece (IoU >=
    umbral) a otra ya conservada dentro de los ultimos `window` frames del
    mismo video, se conserva unicamente la de mayor confianza.

    Nota: en una racha larga (una pizza quieta muchos minutos) se conserva
    aproximadamente una imagen por ventana, no una sola por toda la racha,
    porque pasada la ventana ya puede tratarse de otra pizza.
    """
    if iou_threshold <= 0 or window <= 0:
        return list(candidates), []

    by_video = defaultdict(list)
    for cand in candidates:
        by_video[cand["video"]].append(cand)

    kept_all, dropped_all = [], []

    for video in sorted(by_video):
        ordered = sorted(by_video[video], key=lambda c: (c["frame_index"], -c["conf"]))
        kept = []

        for cand in ordered:
            rival_pos = None
            for pos, other in enumerate(kept):
                if cand["frame_index"] - other["frame_index"] > window:
                    continue
                if iou(cand["box"], other["box"]) >= iou_threshold:
                    rival_pos = pos
                    break

            if rival_pos is None:
                kept.append(cand)
                continue

            rival = kept[rival_pos]
            if cand["conf"] > rival["conf"]:
                kept[rival_pos] = cand
                rival["motivo"] = "duplicado de {}".format(cand["frame"])
                dropped_all.append(rival)
            else:
                cand["motivo"] = "duplicado de {}".format(rival["frame"])
                dropped_all.append(cand)

        kept_all.extend(kept)

    return kept_all, dropped_all


def select_balanced(candidates, target: int, max_per_video: int):
    """
    Elige `target` crops por confianza, repartiendo por turnos entre videos.

    En cada vuelta toma el mejor pendiente de cada video, asi ningun video ni
    hora del dia monopoliza la seleccion. Devuelve (seleccionados, no_usados).
    """
    by_video = defaultdict(list)
    for cand in candidates:
        by_video[cand["video"]].append(cand)

    for video in by_video:
        by_video[video].sort(key=lambda c: c["conf"], reverse=True)
        if max_per_video and max_per_video > 0:
            by_video[video] = by_video[video][:max_per_video]

    selected = []
    videos = sorted(by_video)
    round_index = 0

    while len(selected) < target:
        turn = [by_video[v][round_index] for v in videos if len(by_video[v]) > round_index]
        if not turn:
            break
        turn.sort(key=lambda c: c["conf"], reverse=True)
        for cand in turn:
            if len(selected) >= target:
                break
            selected.append(cand)
        round_index += 1

    chosen_ids = {id(c) for c in selected}
    leftovers = [c for c in candidates if id(c) not in chosen_ids]
    return selected, leftovers


# =============================================================================
# REPORTE HTML (opcional, para QA)
# =============================================================================
def encode_thumb(image_bgr, max_width=240, quality=72):
    import cv2
    if image_bgr is None or getattr(image_bgr, "size", 0) == 0:
        return None
    h, w = image_bgr.shape[:2]
    if w > max_width:
        scale = max_width / float(w)
        image_bgr = cv2.resize(image_bgr, (max_width, max(1, int(h * scale))),
                               interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", image_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    if not ok:
        return None
    return "data:image/jpeg;base64," + base64.b64encode(buf.tobytes()).decode("ascii")


def build_html(stats, per_video, cards):
    rows = "\n".join(
        "<tr><td>{}</td><td class='num'>{}</td><td class='num'>{}</td>"
        "<td class='num'>{}</td><td class='num'>{:.3f}</td></tr>".format(
            html.escape(v["video"]), v["frames"], v["candidatos"], v["seleccionados"], v["conf_media"]
        )
        for v in per_video
    )
    figs = "\n".join(
        "<figure><img src='{}'><figcaption>{}<br><b>conf {:.3f}</b></figcaption></figure>".format(
            c["thumb"], html.escape(c["label"]), c["conf"]
        )
        for c in cards
    )
    return """<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<title>Seleccion de crops - {fecha}</title><style>
:root{{color-scheme:light dark}}
body{{font-family:-apple-system,"Segoe UI",Roboto,sans-serif;margin:0;padding:32px;background:#f6f7f9;color:#1c1e21}}
@media(prefers-color-scheme:dark){{body{{background:#16181c;color:#e8eaed}}section,.kpi{{background:#22252a!important;border-color:#33373d!important}}th{{background:#2b2f35!important}}td,th{{border-color:#33373d!important}}}}
h1{{font-size:21px;margin:0 0 4px}}.sub{{color:#6b7280;font-size:13px;margin-bottom:22px}}
section{{background:#fff;border:1px solid #e3e5e8;border-radius:10px;padding:20px 24px;margin-bottom:18px}}
h2{{font-size:14px;text-transform:uppercase;letter-spacing:.06em;color:#6b7280;margin:0 0 14px}}
.kpis{{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:18px}}
.kpi{{background:#fff;border:1px solid #e3e5e8;border-radius:10px;padding:14px 18px;min-width:140px}}
.kpi .v{{font-size:25px;font-weight:650}}.kpi .l{{font-size:12px;color:#6b7280;margin-top:2px}}
table{{border-collapse:collapse;width:100%;font-size:13px}}
th,td{{border-bottom:1px solid #e8eaed;padding:7px 10px;text-align:left}}
th{{background:#f2f3f5;font-weight:600}}td.num,th.num{{text-align:right;font-variant-numeric:tabular-nums}}
.grid{{display:flex;flex-wrap:wrap;gap:12px}}figure{{margin:0;width:170px}}
figure img{{width:100%;border-radius:6px;display:block;background:#ddd}}
figcaption{{font-size:10.5px;color:#6b7280;margin-top:5px;word-break:break-all;line-height:1.35}}
.note{{font-size:12.5px;color:#6b7280;margin-top:12px;line-height:1.5}}
</style></head><body>
<h1>Seleccion de crops con YOLO</h1>
<div class="sub">{fecha} &middot; conf {conf:.2f} &middot; dedup IoU {iou:.2f} / ventana {win} frames</div>
<div class="kpis">
<div class="kpi"><div class="v">{frames}</div><div class="l">Frames analizados</div></div>
<div class="kpi"><div class="v">{cands}</div><div class="l">Crops detectados</div></div>
<div class="kpi"><div class="v">{dups}</div><div class="l">Duplicados descartados</div></div>
<div class="kpi"><div class="v">{sel}</div><div class="l">Seleccionados para subir</div></div>
<div class="kpi"><div class="v">{confmed:.3f}</div><div class="l">Confianza media</div></div>
</div>
<section><h2>Por video</h2><table><thead><tr><th>Video</th><th class="num">Frames</th>
<th class="num">Candidatos</th><th class="num">Seleccionados</th><th class="num">Conf. media</th>
</tr></thead><tbody>{rows}</tbody></table></section>
<section><h2>Muestra de lo que se sube</h2><div class="grid">{figs}</div>
<div class="note">Las de menor confianza van primero abajo: si ahi ves recortes malos, sube <code>--conf</code>.</div>
</section></body></html>
""".format(
        fecha=stats["fecha"], conf=stats["conf"], iou=stats["dedup_iou"], win=stats["dedup_window"],
        frames=stats["frames"], cands=stats["candidatos"], dups=stats["duplicados"],
        sel=stats["seleccionados"], confmed=stats["conf_media"], rows=rows or "<tr><td>sin datos</td></tr>",
        figs=figs or "<p class='note'>Sin imagenes.</p>",
    )


# =============================================================================
# UTILIDADES DE DISCO
# =============================================================================
def clean_dir(path: Path):
    if not path.exists():
        return
    for item in path.iterdir():
        try:
            if item.is_file() or item.is_symlink():
                item.unlink()
            elif item.is_dir():
                shutil.rmtree(item)
        except OSError as exc:
            print(f"[ADVERTENCIA] No se pudo borrar {item.name}: {exc}")


def iter_images(input_dir: Path):
    for path in sorted(input_dir.iterdir()):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def append_history(base_dir: Path, stats):
    history = base_dir / "historial_selecciones.csv"
    nuevo = not history.exists()
    with open(history, "a", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh, delimiter=";")
        if nuevo:
            writer.writerow([
                "fecha_hora", "videos", "frames", "crops_detectados",
                "duplicados_descartados", "seleccionados", "conf_media",
                "conf_umbral", "objetivo",
            ])
        writer.writerow([
            stats["fecha"], stats["videos"], stats["frames"], stats["candidatos"],
            stats["duplicados"], stats["seleccionados"], "{:.4f}".format(stats["conf_media"]),
            "{:.2f}".format(stats["conf"]), stats["objetivo"],
        ])
    return history


# =============================================================================
# PRINCIPAL
# =============================================================================
def main(argv=None) -> int:
    args = parse_args(argv)

    import cv2

    try:
        import torch
        torch.set_num_threads(max(1, args.threads))
        try:
            torch.set_num_interop_threads(max(1, args.threads))
        except RuntimeError:
            pass
    except ImportError:
        print("[ADVERTENCIA] torch no disponible; se omite el limite de hilos.")

    from ultralytics import YOLO

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    selected_dir = Path(args.selected_dir)
    base_dir = Path(args.base_dir)

    if not input_dir.is_dir():
        print(f"[ERROR] No existe la carpeta de frames: {input_dir}")
        return 1

    model_path = Path(args.model)
    if not model_path.is_file():
        print(f"[ERROR] No existe el modelo: {model_path}")
        return 1

    if args.target_max < args.target_min:
        print("[ERROR] --target_max no puede ser menor que --target_min.")
        return 1

    frames = list(iter_images(input_dir))
    if not frames:
        print(f"[ERROR] No hay frames para procesar en {input_dir}")
        return 1

    print("=" * 64)
    print(" SELECCION DE CROPS CON YOLO (sin clasificador ResNet)")
    print("=" * 64)
    print(f"Frames de entrada : {len(frames)}")
    print(f"Modelo            : {model_path}")
    print(f"Confianza minima  : {args.conf:.2f}")
    print(f"Dedup             : IoU >= {args.dedup_iou:.2f} en ventana de {args.dedup_window} frames")
    print(f"Objetivo          : {args.target_min}-{args.target_max} imagenes (tope {args.max_per_video or 'sin tope'} por video)")
    print(f"Crops a           : {output_dir}")
    print(f"Frames origen a   : {'(desactivado)' if args.no_selected_frames else selected_dir}")
    if args.dry_run:
        print("MODO              : DRY RUN (no escribe nada)")
    print("-" * 64)

    model = YOLO(str(model_path))
    pizza_class_id = resolve_pizza_class_id(model.names, args.pizza_class_name, args.pizza_class_id)

    started = datetime.now()

    candidates = []
    frames_por_video = defaultdict(int)
    errores = 0

    for index, frame_path in enumerate(frames, start=1):
        frames_por_video[get_video_name(frame_path.name)] += 1

        try:
            results = model.predict(source=str(frame_path), conf=args.conf, verbose=False)
        except Exception as exc:
            errores += 1
            print(f"[ERROR] Inferencia fallo en {frame_path.name}: {exc}")
            continue

        if not results:
            errores += 1
            continue

        result = results[0]
        image = result.orig_img
        height, width = image.shape[:2]

        detections = []
        for box in result.boxes:
            if int(box.cls.item()) != pizza_class_id:
                continue
            clamped = clamp_box(*box.xyxy[0].tolist(), width=width, height=height)
            if clamped is None:
                continue
            detections.append((float(box.conf.item()), clamped))

        # Mismo orden que crop_pizza_images.py: arriba-izquierda primero.
        # El indice se calcula sobre TODAS las cajas del frame para que el
        # nombre del archivo sea estable aunque el dedup descarte alguna.
        detections.sort(key=lambda d: (d[1][1], d[1][0]))

        for idx, (conf, box) in enumerate(detections, start=1):
            candidates.append({
                "frame": frame_path.name,
                "frame_path": frame_path,
                "video": get_video_name(frame_path.name),
                "frame_index": get_frame_index(frame_path.name),
                "conf": conf,
                "box": box,
                "nombre_salida": f"{frame_path.stem}_{idx}.png",
            })

        if index % 100 == 0 or index == len(frames):
            print(f"[INFO] {index}/{len(frames)} frames | candidatos: {len(candidates)}")

    total_candidatos = len(candidates)

    # -------------------------------------------------------------------------
    # Dedup + seleccion
    # -------------------------------------------------------------------------
    conservados, duplicados = dedup_candidates(candidates, args.dedup_iou, args.dedup_window)
    print(f"\n[DEDUP] Candidatos: {total_candidatos} | duplicados descartados: {len(duplicados)} "
          f"| quedan: {len(conservados)}")

    objetivo = args.target_max
    seleccionados, sobrantes = select_balanced(conservados, objetivo, args.max_per_video)

    print(f"[SELECCION] Objetivo {objetivo} | seleccionados: {len(seleccionados)} "
          f"| sobrantes sin usar: {len(sobrantes)}")

    if len(seleccionados) < args.target_min:
        print(f"\n[ADVERTENCIA] Solo se seleccionaron {len(seleccionados)} imagenes, "
              f"por debajo del minimo de {args.target_min}.")
        print("              NO se rellena con imagenes aleatorias: revisa si hubo pocos")
        print("              videos, poca actividad, o si --conf esta demasiado alto.")

    conf_media = (sum(c["conf"] for c in seleccionados) / len(seleccionados)) if seleccionados else 0.0

    # -------------------------------------------------------------------------
    # Escritura
    # -------------------------------------------------------------------------
    escritos = 0
    frames_copiados = 0

    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        if not args.no_selected_frames:
            selected_dir.mkdir(parents=True, exist_ok=True)

        if not args.no_clean:
            clean_dir(output_dir)
            if not args.no_selected_frames:
                clean_dir(selected_dir)

        frames_ya_copiados = set()

        for cand in seleccionados:
            image = cv2.imread(str(cand["frame_path"]))
            if image is None:
                print(f"[ERROR] No se pudo leer {cand['frame']}")
                continue

            x1, y1, x2, y2 = cand["box"]
            crop = image[y1:y2, x1:x2]
            if crop.size == 0:
                continue

            destino = output_dir / cand["nombre_salida"]
            if cv2.imwrite(str(destino), crop):
                escritos += 1
            else:
                print(f"[ADVERTENCIA] No se pudo escribir {cand['nombre_salida']}")
                continue

            if not args.no_selected_frames and cand["frame"] not in frames_ya_copiados:
                try:
                    shutil.copy2(cand["frame_path"], selected_dir / cand["frame"])
                    frames_copiados += 1
                    frames_ya_copiados.add(cand["frame"])
                except OSError as exc:
                    print(f"[ADVERTENCIA] No se pudo copiar {cand['frame']}: {exc}")

    # -------------------------------------------------------------------------
    # Estadisticas y reportes
    # -------------------------------------------------------------------------
    sel_por_video = defaultdict(list)
    for cand in seleccionados:
        sel_por_video[cand["video"]].append(cand)

    cand_por_video = defaultdict(int)
    for cand in conservados:
        cand_por_video[cand["video"]] += 1

    per_video = []
    for video in sorted(frames_por_video):
        elegidos = sel_por_video.get(video, [])
        per_video.append({
            "video": video,
            "frames": frames_por_video[video],
            "candidatos": cand_por_video.get(video, 0),
            "seleccionados": len(elegidos),
            "conf_media": (sum(c["conf"] for c in elegidos) / len(elegidos)) if elegidos else 0.0,
        })

    stats = {
        "fecha": started.strftime("%Y-%m-%d %H:%M"),
        "videos": len(frames_por_video),
        "frames": len(frames),
        "candidatos": total_candidatos,
        "duplicados": len(duplicados),
        "seleccionados": len(seleccionados),
        "conf_media": conf_media,
        "conf": args.conf,
        "dedup_iou": args.dedup_iou,
        "dedup_window": args.dedup_window,
        "objetivo": objetivo,
    }

    if not args.dry_run:
        history = append_history(base_dir, stats)
        print(f"\n[HISTORIAL] {history}")

    if args.report_html and seleccionados:
        ordenados = sorted(seleccionados, key=lambda c: c["conf"], reverse=True)
        muestra = ordenados[:12] + ordenados[-12:] if len(ordenados) > 24 else ordenados
        cards = []
        for cand in muestra:
            image = cv2.imread(str(cand["frame_path"]))
            if image is None:
                continue
            x1, y1, x2, y2 = cand["box"]
            thumb = encode_thumb(image[y1:y2, x1:x2])
            if thumb:
                cards.append({"thumb": thumb, "label": cand["nombre_salida"], "conf": cand["conf"]})

        html_path = base_dir / "reporte_seleccion.html"
        html_path.write_text(build_html(stats, per_video, cards), encoding="utf-8")
        print(f"[REPORTE] {html_path}")

    # -------------------------------------------------------------------------
    # Resumen
    # -------------------------------------------------------------------------
    print("\n" + "=" * 64)
    print(" RESUMEN POR VIDEO")
    print("=" * 64)
    print("{:<34} {:>7} {:>11} {:>8} {:>9}".format("video", "frames", "candidatos", "elegidos", "conf med"))
    for v in per_video:
        print("{:<34} {:>7} {:>11} {:>8} {:>9.3f}".format(
            v["video"][:34], v["frames"], v["candidatos"], v["seleccionados"], v["conf_media"]))

    print("\n===== RESUMEN FINAL =====")
    print(f"Frames analizados          : {len(frames)}")
    print(f"Frames con error           : {errores}")
    print(f"Crops detectados           : {total_candidatos}")
    print(f"Duplicados descartados     : {len(duplicados)}")
    print(f"Seleccionados              : {len(seleccionados)} (objetivo {args.target_min}-{args.target_max})")
    print(f"Confianza media            : {conf_media:.3f}")
    if args.dry_run:
        print("Escritura                  : DRY RUN, no se escribio nada")
    else:
        print(f"Crops escritos             : {escritos} -> {output_dir}")
        if not args.no_selected_frames:
            print(f"Frames origen copiados     : {frames_copiados} -> {selected_dir}")
    print(f"Duracion                   : {(datetime.now() - started).total_seconds() / 60:.1f} min")

    if args.fail_under and len(seleccionados) < args.fail_under:
        print(f"\n[ERROR] Se seleccionaron {len(seleccionados)} imagenes, menos que "
              f"--fail_under {args.fail_under}. Se corta el pipeline para no subir un dia incompleto.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
