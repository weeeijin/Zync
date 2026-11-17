import os
from dotenv import load_dotenv

load_dotenv()

# Environment: "development" (default) or "production"
APP_ENV       = os.getenv("APP_ENV", "development").lower()
IS_PRODUCTION = APP_ENV == "production"

# GLM / Z.ai
GLM_API_KEY = os.getenv("GLM_API_KEY", "")
GLM_MODEL   = os.getenv("GLM_MODEL", "glm-4-flash")
GLM_URL     = "https://open.bigmodel.cn/api/paas/v4/chat/completions"

# Databases (dev defaults only — production must set these explicitly)
NEO4J_URI      = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER     = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "" if IS_PRODUCTION else "zync1234")

POSTGRES_URL   = os.getenv(
    "POSTGRES_URL",
    "" if IS_PRODUCTION else "postgresql://zync:zync1234@localhost:5432/zync",
)

QDRANT_HOST    = os.getenv("QDRANT_HOST", "localhost")
QDRANT_PORT    = int(os.getenv("QDRANT_PORT", 6333))

# Admin
ADMIN_SECRET   = os.getenv("ADMIN_SECRET", "" if IS_PRODUCTION else "zync-admin")

# CORS — comma-separated list of allowed browser origins
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",")
    if origin.strip()
]


def _validate_production_config() -> None:
    """Fail fast at startup instead of running prod with insecure defaults."""
    required = {
        "GLM_API_KEY": GLM_API_KEY,
        "NEO4J_PASSWORD": NEO4J_PASSWORD,
        "POSTGRES_URL": POSTGRES_URL,
        "ADMIN_SECRET": ADMIN_SECRET,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise RuntimeError(f"Missing required production settings: {', '.join(missing)}")
    if ADMIN_SECRET == "zync-admin" or len(ADMIN_SECRET) < 16:
        raise RuntimeError("ADMIN_SECRET must be a strong value (16+ chars) in production")
    if "*" in CORS_ORIGINS:
        raise RuntimeError("CORS_ORIGINS must list explicit origins in production, not '*'")


if IS_PRODUCTION:
    _validate_production_config()
