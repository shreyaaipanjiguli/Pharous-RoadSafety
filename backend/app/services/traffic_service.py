"""Async-safe access to TomTom traffic observations."""

from starlette.concurrency import run_in_threadpool

from backend.app.core.config import settings
from risk_engine.live_providers import fetch_traffic_for_segment


async def get_segment_traffic(latitude: float, longitude: float):
    """Return a validated traffic observation, or None if unavailable."""
    if not settings.tomtom_api_key:
        return None

    return await run_in_threadpool(
        fetch_traffic_for_segment,
        latitude,
        longitude,
        api_key=settings.tomtom_api_key,
    )
