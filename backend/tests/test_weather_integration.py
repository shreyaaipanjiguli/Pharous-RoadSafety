
import asyncio
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from backend.app.integrations.weather import (
    WeatherForecastError,
    get_weather_forecast,
)


def test_returns_forecast_near_arrival_time():
    payload = {
        "hourly": {
            "time": [
                "2026-10-28T10:00",
                "2026-10-28T11:00",
            ],
            "precipitation": [2.5, 8.0],
            "visibility": [10000, 3000],
        }
    }

    response = MagicMock()
    response.raise_for_status.return_value = None
    response.json.return_value = payload

    client = AsyncMock()
    client.get.return_value = response

    with patch(
        "backend.app.integrations.weather.httpx.AsyncClient"
    ) as client_class:
        client_class.return_value.__aenter__.return_value = client

        result = asyncio.run(
            get_weather_forecast(
                12.85,
                75.60,
                datetime(
                    2026, 10, 28, 10, 50, tzinfo=timezone.utc
                ),
            )
        )

    assert result["precipitation_mm"] == 8.0
    assert result["visibility_m"] == 3000.0
    assert result["forecast_time"] == "2026-10-28T11:00:00+00:00"
    assert result["source"] == "Open-Meteo"


def test_rejects_invalid_coordinates():
    with pytest.raises(ValueError, match="Latitude"):
        asyncio.run(
            get_weather_forecast(
                95,
                75.6,
                datetime(
                    2026, 10, 28, 10, tzinfo=timezone.utc
                ),
            )
        )


def test_rejects_missing_hourly_data():
    response = MagicMock()
    response.raise_for_status.return_value = None
    response.json.return_value = {}

    client = AsyncMock()
    client.get.return_value = response

    with patch(
        "backend.app.integrations.weather.httpx.AsyncClient"
    ) as client_class:
        client_class.return_value.__aenter__.return_value = client

        with pytest.raises(WeatherForecastError):
            asyncio.run(
                get_weather_forecast(
                    12.85,
                    75.60,
                    datetime(
                        2026, 10, 28, 10, tzinfo=timezone.utc
                    ),
                )
            )


def test_handles_http_failure():
    client = AsyncMock()
    client.get.side_effect = httpx.ConnectError(
        "network unavailable"
    )

    with patch(
        "backend.app.integrations.weather.httpx.AsyncClient"
    ) as client_class:
        client_class.return_value.__aenter__.return_value = client

        with pytest.raises(WeatherForecastError):
            asyncio.run(
                get_weather_forecast(
                    12.85,
                    75.60,
                    datetime(
                        2026, 10, 28, 10, tzinfo=timezone.utc
                    ),
                )
            )

@pytest.mark.parametrize(
    "latitude,longitude",
    [
        (float("nan"), 75.6),
        (float("inf"), 75.6),
        (12.85, float("nan")),
        (12.85, float("-inf")),
    ],
)
def test_rejects_non_finite_coordinates(latitude, longitude):
    with pytest.raises(ValueError):
        asyncio.run(
            get_weather_forecast(
                latitude, longitude,
                datetime(2026, 10, 28, 10, tzinfo=timezone.utc),
            )
        )


def _run_forecast_with_payload(payload):
    response = MagicMock()
    response.raise_for_status.return_value = None
    response.json.return_value = payload
    client = AsyncMock()
    client.get.return_value = response

    with patch(
        "backend.app.integrations.weather.httpx.AsyncClient"
    ) as client_class:
        client_class.return_value.__aenter__.return_value = client
        return asyncio.run(
            get_weather_forecast(
                12.85, 75.60,
                datetime(2026, 10, 28, 10, tzinfo=timezone.utc),
            )
        )


@pytest.mark.parametrize(
    "precipitation,visibility",
    [
        ([float("nan")], [10000]),
        ([float("inf")], [10000]),
        ([2.5], [float("nan")]),
        ([2.5], [float("inf")]),
        ([-1], [10000]),
        ([2.5], [-1]),
    ],
)
def test_rejects_invalid_weather_measurements(precipitation, visibility):
    payload = {
        "hourly": {
            "time": ["2026-10-28T10:00"],
            "precipitation": precipitation,
            "visibility": visibility,
        }
    }
    with pytest.raises(WeatherForecastError):
        _run_forecast_with_payload(payload)


@pytest.mark.parametrize("payload", [[], "invalid", 123, None])
def test_rejects_non_object_api_payload(payload):
    with pytest.raises(WeatherForecastError):
        _run_forecast_with_payload(payload)


def test_preserves_timezone_offset_in_forecast_timestamp():
    payload = {
        "hourly": {
            "time": ["2026-10-28T12:00+02:00"],
            "precipitation": [2.5],
            "visibility": [10000],
        }
    }
    result = _run_forecast_with_payload(payload)
    assert result["forecast_time"] == "2026-10-28T10:00:00+00:00"


@pytest.mark.parametrize(
    "times",
    [
        ["2026-10-28T10:00", "2026-10-28T10:00"],
        ["2026-10-28T11:00", "2026-10-28T10:00"],
    ],
)
def test_rejects_duplicate_or_non_monotonic_forecast_timestamps(times):
    payload = {
        "hourly": {
            "time": times,
            "precipitation": [2.5, 3.0],
            "visibility": [10000, 9000],
        }
    }
    with pytest.raises(WeatherForecastError):
        _run_forecast_with_payload(payload)


def test_preserves_missing_weather_measurements_as_unknown():
    payload = {
        "hourly": {
            "time": ["2026-10-28T10:00"],
            "precipitation": [None],
            "visibility": [None],
        }
    }
    result = _run_forecast_with_payload(payload)
    assert result["precipitation_mm"] is None
    assert result["visibility_m"] is None
