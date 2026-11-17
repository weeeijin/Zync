"""Liveness / readiness probes.

/health  — liveness: the process is up (cheap, no dependencies).
/ready   — readiness: every backing service answers. Used by the deploy
           smoke test, load balancers and uptime monitoring.
"""
import asyncio
import time

import asyncpg

from config import POSTGRES_URL
from db.neo4j_client import get_driver
from db.qdrant_client import get_client

PROBE_TIMEOUT_S = 3.0


async def _check_postgres() -> None:
    conn = await asyncpg.connect(POSTGRES_URL, timeout=PROBE_TIMEOUT_S)
    try:
        await conn.execute("SELECT 1")
    finally:
        await conn.close()


async def _check_neo4j() -> None:
    driver = get_driver()
    if driver is None:
        raise RuntimeError("driver not initialised")
    await driver.verify_connectivity()


async def _check_qdrant() -> None:
    client = get_client()
    if client is None:
        raise RuntimeError("client not initialised")
    await asyncio.to_thread(client.get_collections)


_CHECKS = {
    "postgres": _check_postgres,
    "neo4j": _check_neo4j,
    "qdrant": _check_qdrant,
}


async def _run(name: str, check) -> tuple[str, dict]:
    started = time.perf_counter()
    try:
        await asyncio.wait_for(check(), timeout=PROBE_TIMEOUT_S)
        status = {"status": "ok"}
    except Exception as exc:  # report, never raise, from a probe
        status = {"status": "error", "error": type(exc).__name__}
    status["latency_ms"] = round((time.perf_counter() - started) * 1000, 1)
    return name, status


async def readiness() -> tuple[bool, dict]:
    results = dict(await asyncio.gather(*(_run(n, c) for n, c in _CHECKS.items())))
    ok = all(r["status"] == "ok" for r in results.values())
    return ok, results
