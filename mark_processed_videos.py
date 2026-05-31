from pathlib import Path

BASE_DIR = Path(r"C:\pizza_pipeline")
PROCESSED_FILE = BASE_DIR / "processed_videos.txt"
PENDING_FILE = BASE_DIR / "pending_videos.txt"


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []

    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def main() -> None:
    pending = read_lines(PENDING_FILE)

    if not pending:
        print("No hay videos pendientes para marcar como procesados.")
        if PENDING_FILE.exists():
            PENDING_FILE.unlink()
        return

    processed = set(read_lines(PROCESSED_FILE))
    new_videos = []

    for video in pending:
        if video not in processed:
            processed.add(video)
            new_videos.append(video)

    if new_videos:
        with PROCESSED_FILE.open("a", encoding="utf-8") as f:
            for video in new_videos:
                f.write(video + "\n")

    if PENDING_FILE.exists():
        PENDING_FILE.unlink()

    duplicates = len(pending) - len(new_videos)
    print(f"Videos marcados como procesados: {len(new_videos)}")
    if duplicates:
        print(f"Videos ya marcados previamente: {duplicates}")


if __name__ == "__main__":
    main()
