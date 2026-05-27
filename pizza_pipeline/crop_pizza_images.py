import argparse
from pathlib import Path

import cv2
from ultralytics import YOLO

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Detect pizzas in images and save one cropped PNG per detected pizza. "
            "Outputs are named <original_stem>_1.png, <original_stem>_2.png, ..."
        )
    )
    parser.add_argument(
        "-mod",
        "--model",
        required=True,
        help="Path to the YOLO/Ultralytics model file.",
    )
    parser.add_argument(
        "-i",
        "--input_dir",
        required=True,
        help="Folder containing source pizza images.",
    )
    parser.add_argument(
        "-o",
        "--output_dir",
        required=True,
        help="Folder to write cropped pizza images.",
    )
    parser.add_argument(
        "--pizza_class_name",
        default="pizza",
        help=(
            "Class name to crop (default: pizza). If this class name is not present in model.names, "
            "--pizza_class_id will be used."
        ),
    )
    parser.add_argument(
        "--pizza_class_id",
        type=int,
        default=53,
        help="Fallback class ID for pizza when class name lookup fails (COCO pizza is 53).",
    )
    parser.add_argument(
        "--conf",
        type=float,
        default=0.25,
        help="Detection confidence threshold.",
    )
    return parser.parse_args()


def resolve_pizza_class_id(model: YOLO, class_name: str, fallback_id: int) -> int:
    names = model.names if isinstance(model.names, dict) else {}
    lowered = {str(v).lower(): int(k) for k, v in names.items()}

    if class_name.lower() in lowered:
        return lowered[class_name.lower()]

    print(
        f"Warning: class name '{class_name}' not found in model classes; "
        f"using class id {fallback_id}."
    )
    return fallback_id


def iter_images(input_dir: Path):
    for path in sorted(input_dir.iterdir()):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def main() -> None:
    args = parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    if not input_dir.exists() or not input_dir.is_dir():
        raise FileNotFoundError(f"Input directory does not exist or is not a directory: {input_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)

    model = YOLO(args.model)
    pizza_class_id = resolve_pizza_class_id(model, args.pizza_class_name, args.pizza_class_id)

    source_images = list(iter_images(input_dir))
    if not source_images:
        print(f"No supported image files found in {input_dir}.")
        return

    total_crops = 0

    for image_path in source_images:
        results = model.predict(source=str(image_path), conf=args.conf, verbose=False)
        if not results:
            print(f"No result returned for {image_path.name}; skipping.")
            continue

        result = results[0]
        image = result.orig_img

        pizza_boxes = []
        for box in result.boxes:
            if int(box.cls.item()) != pizza_class_id:
                continue

            x1, y1, x2, y2 = box.xyxy[0].tolist()
            h, w = image.shape[:2]

            x1 = max(0, min(int(x1), w - 1))
            y1 = max(0, min(int(y1), h - 1))
            x2 = max(1, min(int(x2), w))
            y2 = max(1, min(int(y2), h))

            if x2 <= x1 or y2 <= y1:
                continue

            pizza_boxes.append((x1, y1, x2, y2))

        pizza_boxes.sort(key=lambda b: (b[1], b[0]))

        if not pizza_boxes:
            print(f"No pizzas found in {image_path.name}.")
            continue

        for idx, (x1, y1, x2, y2) in enumerate(pizza_boxes, start=1):
            crop = image[y1:y2, x1:x2]
            if crop.size == 0:
                continue

            output_path = output_dir / f"{image_path.stem}_{idx}.png"
            cv2.imwrite(str(output_path), crop)
            total_crops += 1

        print(f"{image_path.name}: saved {len(pizza_boxes)} crop(s).")

    print(f"Done. Saved {total_crops} total cropped pizza image(s) to {output_dir}.")


if __name__ == "__main__":
    main()
