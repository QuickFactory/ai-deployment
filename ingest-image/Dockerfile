# OCR + ingest sidecar.
# jbarlow83/ocrmypdf bundles ocrmypdf, Tesseract, Ghostscript and Python.
FROM jbarlow83/ocrmypdf:latest

# Extra Tesseract language packs: uncomment / extend as needed and keep
# OCR_LANGUAGES in .env in sync (e.g. OCR_LANGUAGES=eng+deu).
# RUN apt-get update && apt-get install -y --no-install-recommends \
#         tesseract-ocr-deu tesseract-ocr-fra \
#     && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --break-system-packages requests || \
    pip install --no-cache-dir requests

COPY ingest_watcher.py /app/ingest_watcher.py

# Base image's ENTRYPOINT is ocrmypdf itself; override to run the watcher.
ENTRYPOINT []
CMD ["python3", "-u", "/app/ingest_watcher.py"]
