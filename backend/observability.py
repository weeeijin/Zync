"""Logging, request IDs and Prometheus metrics for the Zync API.

- JSON logs on stdout (LOG_FORMAT=json, default in production) so Loki can
  index fields; human-readable text logs in development.
- Every request gets an X-Request-ID (taken from Caddy or generated), echoed in
  the response and attached to every log line written while handling it.
- Prometheus metrics for HTTP traffic and GLM (LLM) calls at GET /metrics.
  Works with multiple uvicorn workers via PROMETHEUS_MULTIPROC_DIR.
"""
import contextvars
import json
import logging
import os
import sys
import time
import uuid
from contextlib import contextmanager

from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    multiprocess,
)
from starlette.responses import Response

request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")

# ── Logging ──────────────────────────────────────────────────────────────────
_RESERVED = set(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S") + f".{int(record.msecs):03d}Z",
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
            "request_id": request_id_var.get(),
        }
        # Anything passed via logger.info(..., extra={...})
        entry.update({k: v for k, v in vars(record).items() if k not in _RESERVED})
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


class _RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        return True


def configure_logging() -> None:
    level = os.getenv("LOG_LEVEL", "INFO").upper()
    default_format = "json" if os.getenv("APP_ENV", "development") == "production" else "text"
    fmt = os.getenv("LOG_FORMAT", default_format)

    handler = logging.StreamHandler(sys.stdout)
    if fmt == "json":
        formatter: logging.Formatter = JsonFormatter()
        formatter.converter = time.gmtime
    else:
        handler.addFilter(_RequestIdFilter())
        formatter = logging.Formatter("%(asctime)s %(levelname)-7s %(name)s [%(request_id)s] %(message)s")
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
    # Our middleware writes access logs with more context; silence uvicorn's
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers[:] = []
        logging.getLogger(name).propagate = True
    logging.getLogger("uvicorn.access").disabled = True
    logging.getLogger("httpx").setLevel(logging.WARNING)


# ── Metrics ──────────────────────────────────────────────────────────────────
_LATENCY_BUCKETS = (0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300)

HTTP_REQUESTS = Counter(
    "zync_http_requests_total", "HTTP requests handled", ["method", "route", "status"]
)
HTTP_DURATION = Histogram(
    "zync_http_request_duration_seconds",
    "Time to fully serve a request (streaming responses: until the stream ends)",
    ["method", "route"],
    buckets=_LATENCY_BUCKETS,
)
HTTP_IN_PROGRESS = Gauge(
    "zync_http_requests_in_progress", "Requests currently being served", ["method"],
    multiprocess_mode="livesum",
)

LLM_REQUESTS = Counter(
    "zync_llm_requests_total", "Calls to the GLM API", ["mode", "model", "outcome"]
)
LLM_DURATION = Histogram(
    "zync_llm_request_duration_seconds", "GLM API call duration", ["mode", "model"],
    buckets=(0.5, 1, 2.5, 5, 10, 20, 30, 60, 90, 120, 180),
)
LLM_FIRST_TOKEN = Histogram(
    "zync_llm_time_to_first_token_seconds", "Streaming: time until the first token arrives", ["model"],
    buckets=(0.25, 0.5, 1, 2, 4, 8, 15, 30, 60),
)
LLM_TOKENS = Counter(
    "zync_llm_tokens_total", "Tokens consumed (as reported by the GLM API)", ["model", "kind"]
)

_SKIP_ACCESS_LOG = {"/health", "/metrics"}


def record_llm_usage(model: str, usage: dict | None) -> None:
    if not usage:
        return
    for kind in ("prompt_tokens", "completion_tokens"):
        if usage.get(kind):
            LLM_TOKENS.labels(model=model, kind=kind.removesuffix("_tokens")).inc(usage[kind])


@contextmanager
def track_llm_call(mode: str, model: str):
    """Time a GLM call and count it by outcome (success / http_<code> / timeout / error)."""
    import httpx  # local import keeps this module importable without httpx

    started = time.perf_counter()
    outcome = "success"
    try:
        yield
    except httpx.HTTPStatusError as exc:
        outcome = f"http_{exc.response.status_code}"
        raise
    except httpx.TimeoutException:
        outcome = "timeout"
        raise
    except Exception:
        outcome = "error"
        raise
    finally:
        LLM_DURATION.labels(mode=mode, model=model).observe(time.perf_counter() - started)
        LLM_REQUESTS.labels(mode=mode, model=model, outcome=outcome).inc()


def metrics_endpoint(_request=None) -> Response:
    if os.getenv("PROMETHEUS_MULTIPROC_DIR"):
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
        data = generate_latest(registry)
    else:
        data = generate_latest()
    return Response(data, media_type=CONTENT_TYPE_LATEST)


# ── ASGI middleware (pure ASGI: safe for streaming/SSE responses) ───────────
class ObservabilityMiddleware:
    def __init__(self, app):
        self.app = app
        self.log = logging.getLogger("zync.access")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = dict(scope.get("headers") or [])
        incoming = headers.get(b"x-request-id", b"").decode("latin-1")
        request_id = incoming if 0 < len(incoming) <= 128 else uuid.uuid4().hex
        token = request_id_var.set(request_id)

        method = scope["method"]
        status = 500
        started = time.perf_counter()
        HTTP_IN_PROGRESS.labels(method=method).inc()

        async def send_wrapper(message):
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
                message.setdefault("headers", [])
                message["headers"] = list(message["headers"]) + [(b"x-request-id", request_id.encode())]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            duration = time.perf_counter() - started
            HTTP_IN_PROGRESS.labels(method=method).dec()
            # Route template (e.g. /api/zone), never the raw path → bounded cardinality
            route = getattr(scope.get("route"), "path", None) or "unmatched"
            HTTP_REQUESTS.labels(method=method, route=route, status=str(status)).inc()
            HTTP_DURATION.labels(method=method, route=route).observe(duration)

            if scope.get("path") not in _SKIP_ACCESS_LOG:
                level = logging.ERROR if status >= 500 else logging.INFO
                self.log.log(
                    level, "%s %s %s", method, scope.get("path"), status,
                    extra={
                        "http_method": method,
                        "http_path": scope.get("path"),
                        "http_route": route,
                        "http_status": status,
                        "duration_ms": round(duration * 1000, 1),
                        "client_ip": headers.get(b"x-forwarded-for", b"").decode("latin-1").split(",")[0]
                        or (scope.get("client") or ("-",))[0],
                    },
                )
            request_id_var.reset(token)
