"""Metrics must label requests by full route template (with the /api prefix)."""
from fastapi import APIRouter, FastAPI
from httpx import ASGITransport, AsyncClient

from observability import route_template


def _app_capturing_routes():
    router = APIRouter()

    @router.post("/zone")
    async def zone():
        return {}

    @router.get("/items/{item_id}")
    async def item(item_id: str):
        return {}

    app = FastAPI()
    app.include_router(router, prefix="/api")

    @app.get("/health")
    async def health():
        return {}

    seen = []

    class Capture:
        def __init__(self, inner):
            self.inner = inner

        async def __call__(self, scope, receive, send):
            await self.inner(scope, receive, send)
            if scope["type"] == "http":
                seen.append(route_template(scope))

    app.add_middleware(Capture)
    return app, seen


async def test_route_templates_include_router_prefix():
    app, seen = _app_capturing_routes()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
        await client.post("/api/zone")
        await client.get("/api/items/abc123")
        await client.get("/health")
        await client.get("/wp-login.php")  # scanner noise

    assert seen == ["/api/zone", "/api/items/{item_id}", "/health", "unmatched"]
