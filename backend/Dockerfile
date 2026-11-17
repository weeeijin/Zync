# syntax=docker/dockerfile:1.7
# Build context: repository root  →  docker build -f backend/Dockerfile .
# (the backend reads ../data/*.json, so the data folder must be in the image)

# ── Stage 1: install dependencies into an isolated virtualenv ────────────────
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY backend/requirements.txt /tmp/requirements.txt
# Packaging tools aren't needed at runtime — drop them (and their CVEs)
RUN pip install -r /tmp/requirements.txt \
 && pip uninstall -y pip setuptools wheel

# ── Stage 2: minimal runtime image, non-root ────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    APP_ENV=production \
    WEB_CONCURRENCY=2 \
    LOG_FORMAT=json \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus \
    FASTEMBED_CACHE_PATH=/home/app/.cache/fastembed

# Pick up OS security fixes released after the base image was built, and
# remove the base image's pip/setuptools (unused at runtime)
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && (python -m pip uninstall -y pip setuptools wheel || true)

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --create-home app \
 && mkdir -p /home/app/.cache/fastembed \
 && chown -R app:app /home/app

COPY --from=builder /opt/venv /opt/venv
COPY --chmod=0755 backend/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Mirror the repo layout so ../../data paths resolve: /srv/zync/{backend,data}
WORKDIR /srv/zync/backend
COPY --chown=app:app data/    /srv/zync/data/
COPY --chown=app:app backend/ /srv/zync/backend/

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200 else 1)"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# WEB_CONCURRENCY sets the worker count; proxy headers come from Caddy
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
