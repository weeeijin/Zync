from observability import ObservabilityMiddleware, configure_logging, metrics_endpoint

configure_logging()  # before anything else logs

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from routes.pipeline import router as pipeline_router
from routes.validate import router as validate_router
from routes.upload   import router as upload_router
from routes.admin    import router as admin_router
from routes.zone      import router as zone_router
from routes.diagnosis import router as diagnosis_router
from config import CORS_ORIGINS
from health import readiness

app = FastAPI(title="Zync API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Outermost: sees every request, including CORS preflights
app.add_middleware(ObservabilityMiddleware)

# Prometheus scrape target — internal only (Caddy doesn't route /metrics)
app.add_route("/metrics", metrics_endpoint, include_in_schema=False)

app.include_router(pipeline_router, prefix="/api")
app.include_router(validate_router, prefix="/api")
app.include_router(upload_router,   prefix="/api")
app.include_router(admin_router,    prefix="/api")
app.include_router(zone_router,      prefix="/api")
app.include_router(diagnosis_router, prefix="/api")

@app.get("/health")
async def health():
    return {"status": "ok", "service": "Zync API"}


@app.get("/ready")
async def ready(response: Response):
    ok, checks = await readiness()
    if not ok:
        response.status_code = 503
    return {"status": "ok" if ok else "degraded", "checks": checks}
