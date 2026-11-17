"""Turn unexpected exceptions into safe client-facing errors.

The full traceback is logged server-side with a short reference ID; the client
only sees a generic message plus that ID, so internals (hostnames, upstream
API responses, stack traces) never leak to the browser.
"""
import logging
import uuid

logger = logging.getLogger("zync.errors")


def safe_error(exc: Exception, context: str) -> dict:
    error_id = uuid.uuid4().hex[:12]
    logger.error(
        "Unhandled error in %s [error_id=%s]", context, error_id,
        exc_info=(type(exc), exc, exc.__traceback__),
    )
    return {
        "status": "error",
        "message": f"Something went wrong while processing your request (ref {error_id}).",
        "error_id": error_id,
    }
