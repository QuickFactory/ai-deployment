# OCR + ingest sidecar.
# jbarlow83/ocrmypdf bundles ocrmypdf, Tesseract, Ghostscript and Python.
FROM jbarlow83/ocrmypdf:latest

USER root
RUN python3 -m pip install --no-cache-dir --break-system-packages requests \
    || (python3 -m ensurepip --upgrade && \
        python3 -m pip install --no-cache-dir --break-system-packages requests)

COPY --chown=app:app ingest_watcher.py /app/ingest_watcher.py
USER app

# Base image's ENTRYPOINT is ocrmypdf itself; override to run the watcher.
ENTRYPOINT []
CMD ["python3", "-u", "/app/ingest_watcher.py"]