#!/usr/bin/env python3
"""
Folder-drop RAG ingestion for the Hermes stack.

Watches /data/inbox. For each new, stable file:
  1. If it's a PDF        -> ocrmypdf --skip-text  (OCR only pages lacking a text layer)
  2. If it's an image scan-> ocrmypdf --image-dpi 300 (convert to searchable PDF)
  3. Other supported types (txt/md/docx/csv/html/...) pass through untouched.
  4. POST the result to rag_api /embed with the internal API key.
  5. Move original to /data/processed or /data/failed. Record in /data/manifest.json.

Design constraints (4GB VPS): strictly serial, --jobs 1 for OCR, container is
mem-limited in docker-compose. Polling (not inotify) so files arriving via
scp/rsync/network mounts are handled correctly.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import requests

RAG_API_URL = os.environ.get("RAG_API_URL", "http://rag_api:8000").rstrip("/")
RAG_API_KEY = os.environ["RAG_API_KEY"]
OCR_LANGUAGES = os.environ.get("OCR_LANGUAGES", "eng")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "20"))
OCR_TIMEOUT = int(os.environ.get("OCR_TIMEOUT", "1800"))          # whole-file cap
TESSERACT_PAGE_TIMEOUT = os.environ.get("TESSERACT_PAGE_TIMEOUT", "300")
ENTITY_ID = os.environ.get("RAG_ENTITY_ID", "hermes-shared")       # one shared collection

DATA = Path("/data")
INBOX = DATA / "inbox"
PROCESSED = DATA / "processed"
FAILED = DATA / "failed"
MANIFEST = DATA / "manifest.json"

PDF_EXT = {".pdf"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp"}
PASSTHROUGH_EXT = {".txt", ".md", ".markdown", ".csv", ".tsv", ".json",
                   ".html", ".htm", ".docx", ".pptx", ".xlsx", ".epub", ".rst"}

def log(msg: str) -> None:
    print(f"[ingest] {time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)

def load_manifest() -> dict:
    if MANIFEST.exists():
        try:
            return json.loads(MANIFEST.read_text())
        except json.JSONDecodeError:
            log("WARN: manifest.json corrupt, starting fresh (old copy kept as .bak)")
            shutil.copy2(MANIFEST, MANIFEST.with_suffix(".json.bak"))
    return {}

def save_manifest(m: dict) -> None:
    tmp = MANIFEST.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(m, indent=2))
    tmp.replace(MANIFEST)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def unique_dest(folder: Path, name: str) -> Path:
    dest = folder / name
    i = 1
    while dest.exists():
        dest = folder / f"{Path(name).stem}.{i}{Path(name).suffix}"
        i += 1
    return dest

def run_ocr(src: Path, workdir: Path) -> Path:
    """Return path to a searchable PDF derived from src (PDF or image)."""
    out = workdir / (src.stem + ".ocr.pdf")
    cmd = ["ocrmypdf",
           "--jobs", "1",                         # serial pages: bounds memory
           "--language", OCR_LANGUAGES,
           "--tesseract-timeout", TESSERACT_PAGE_TIMEOUT,
           "--optimize", "0"]                     # skip optimization: saves RAM/CPU
    if src.suffix.lower() in PDF_EXT:
        cmd += ["--skip-text"]                    # OCR only pages with no text layer
    else:
        cmd += ["--image-dpi", "300"]             # image scan -> searchable PDF
    cmd += [str(src), str(out)]

    res = subprocess.run(cmd, capture_output=True, text=True, timeout=OCR_TIMEOUT)
    # Exit 0 = OCR done. ocrmypdf uses dedicated codes for "nothing to do"
    # (PriorOcrFound / page-count edge cases); treat a produced output as success,
    # and for --skip-text a fully digital PDF may come back unchanged.
    if res.returncode == 0 and out.exists():
        return out
    if src.suffix.lower() in PDF_EXT and res.returncode != 0:
        log(f"WARN: ocrmypdf rc={res.returncode} on {src.name}; "
            f"submitting original PDF as-is. stderr tail: {res.stderr[-400:]}")
        return src
    raise RuntimeError(f"ocrmypdf failed rc={res.returncode}: {res.stderr[-400:]}")

def embed(path: Path, file_id: str) -> None:
    with path.open("rb") as f:
        r = requests.post(
            f"{RAG_API_URL}/embed",
            headers={"Authorization": f"Bearer {RAG_API_KEY}"},
            data={"file_id": file_id, "entity_id": ENTITY_ID},
            files={"file": (path.name, f)},
            timeout=600,
        )
    if r.status_code != 200:
        raise RuntimeError(f"rag_api /embed HTTP {r.status_code}: {r.text[:400]}")

def process(path: Path, manifest: dict) -> None:
    digest = sha256_file(path)
    if digest in manifest:
        log(f"SKIP (duplicate of {manifest[digest]['name']}): {path.name}")
        path.rename(unique_dest(PROCESSED, path.name))
        return

    ext = path.suffix.lower()
    with tempfile.TemporaryDirectory(dir=str(DATA)) as tmp:
        workdir = Path(tmp)
        if ext in PDF_EXT or ext in IMAGE_EXT:
            log(f"OCR pass: {path.name}")
            submit = run_ocr(path, workdir)
        elif ext in PASSTHROUGH_EXT:
            submit = path
        else:
            raise RuntimeError(f"unsupported extension: {ext}")

        log(f"Embedding: {submit.name} (file_id={digest[:12]}...)")
        embed(submit, digest)

    manifest[digest] = {"file_id": digest, "name": path.name,
                        "ingested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    save_manifest(manifest)
    path.rename(unique_dest(PROCESSED, path.name))
    log(f"DONE: {path.name}")

def main() -> None:
    for d in (INBOX, PROCESSED, FAILED):
        d.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    log(f"Watching {INBOX} every {POLL_INTERVAL}s (langs={OCR_LANGUAGES}, entity={ENTITY_ID})")

    sizes: dict[str, int] = {}
    while True:
        try:
            for path in sorted(p for p in INBOX.iterdir() if p.is_file()):
                if path.name.startswith("."):
                    continue
                size = path.stat().st_size
                # Stability check: only touch files whose size held for one full cycle.
                if sizes.get(str(path)) != size:
                    sizes[str(path)] = size
                    continue
                sizes.pop(str(path), None)
                try:
                    process(path, manifest)
                except Exception as exc:                      # noqa: BLE001
                    log(f"FAILED {path.name}: {exc}")
                    if path.exists():
                        path.rename(unique_dest(FAILED, path.name))
        except Exception as exc:                              # noqa: BLE001
            log(f"loop error: {exc}")
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
