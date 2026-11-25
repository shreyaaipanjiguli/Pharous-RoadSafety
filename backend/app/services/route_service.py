
"""Route processing and risk assessment built on the existing OSRM integration."""

import math
from typing import Any

from geoalchemy2 import Geography
from sqlalchemy import cast, func, select
from sqlalchemy.orm import Session

from ..models.segment import RoadSegment
from .risk_service import assess_segment_risk


SEGMENT_MATCH_RADIUS_M = 100.0

HEAVY_RAIN_THRESHOLD_MM_PER_HOUR = 15.0
LOW_VISIBILITY_THRESHOLD_M = 1000.0
SLOPE_THRESHOLD_PERCENT = 6.0

RISK_COLORS = {
    "Green": "green",
    "Yellow": "yellow",
    "Orange": "orange",
    "Red": "red",
}


def get_risk_level(score: float) -> str:
    """Map a risk score to the existing scorer's risk levels."""
    if score <= 30:
        return "Green"
    if score <= 50:
        return "Yellow"
    if score <= 75:
        return "Orange"
    return "Red"


def _parse_weather_value(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        val = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    if not math.isfinite(val) or val < 0:
        return None
    return val


def classify_weather_risk(
    weather: dict[str, Any] | None,
) -> tuple[bool | None, bool | None]:
    """Classify raw weather forecast values into risk flags.

    Returns:
        (heavy_rain, low_visibility)

    Missing, malformed, negative, NaN or infinite values remain unknown (None)
    rather than being treated as safe. Precipitation and visibility are validated
    independently: an invalid measurement in one does not discard a valid
    measurement in the other.
    """
    if not isinstance(weather, dict):
        return None, None

    precipitation = _parse_weather_value(weather.get("precipitation_mm"))
    visibility = _parse_weather_value(weather.get("visibility_m"))

    heavy_rain = (
        (precipitation > HEAVY_RAIN_THRESHOLD_MM_PER_HOUR)
        if precipitation is not None
        else None
    )
    low_visibility = (
        (visibility < LOW_VISIBILITY_THRESHOLD_M)
        if visibility is not None
        else None
    )

    return heavy_rain, low_visibility


def create_segments(
    coordinates: list[list[float]],
    edge_distances: list[float],
    target_length_m: float = 1000,
) -> list[dict[str, Any]]:
    """Group consecutive OSRM edges into approximately 1 km segments."""
    if (
        isinstance(target_length_m, bool)
        or not isinstance(target_length_m, (int, float))
        or not math.isfinite(target_length_m)
        or target_length_m <= 0
    ):
        raise ValueError(
            "target_length_m must be a finite number greater than zero"
        )

    if len(coordinates) < 2:
        raise ValueError("At least two route coordinates are required")

    if len(edge_distances) != len(coordinates) - 1:
        raise ValueError(
            "Edge-distance count must equal coordinate count minus one"
        )

    for index, point in enumerate(coordinates):
        if (
            not isinstance(point, (list, tuple))
            or len(point) != 2
            or any(
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                for value in point
            )
            or not -180 <= point[0] <= 180
            or not -90 <= point[1] <= 90
        ):
            raise ValueError(
                f"Invalid route coordinate at index {index}"
            )

    for index, distance in enumerate(edge_distances):
        if (
            isinstance(distance, bool)
            or not isinstance(distance, (int, float))
            or not math.isfinite(distance)
            or distance < 0
        ):
            raise ValueError(
                f"Invalid edge distance at index {index}"
            )

    segments: list[dict[str, Any]] = []
    segment_coordinates = [coordinates[0]]
    segment_distance = 0.0
    segment_id = 1

    for index, distance in enumerate(edge_distances):
        edge_end = coordinates[index + 1]

        segment_distance += distance
        segment_coordinates.append(edge_end)

        if segment_distance >= target_length_m:
            segment_geometry = segment_coordinates.copy()

            segments.append({
                "segment_id": segment_id,
                "start": segment_geometry[0],
                "end": segment_geometry[-1],
                "coordinates": segment_geometry,
                "geometry": {
                    "type": "LineString",
                    "coordinates": segment_geometry,
                },
                "length_m": round(segment_distance, 2),
                "risk_status": "not_assessed",
            })

            segment_id += 1
            segment_coordinates = [edge_end]
            segment_distance = 0.0

    if segment_distance > 0:
        segment_geometry = segment_coordinates.copy()

        segments.append({
            "segment_id": segment_id,
            "start": segment_geometry[0],
            "end": segment_geometry[-1],
            "coordinates": segment_geometry,
            "geometry": {
                "type": "LineString",
                "coordinates": segment_geometry,
            },
            "length_m": round(segment_distance, 2),
            "risk_status": "not_assessed",
        })

    return segments


def process_osrm_route(route: dict[str, Any]) -> dict[str, Any]:
    """Validate and normalize one OSRM route without inventing risk scores."""
    try:
        coordinates = route["geometry"]["coordinates"]
        legs = route["legs"]
        distance_m = float(route["distance"])
        duration_s = float(route["duration"])
        annotations = [
            leg["annotation"]["distance"] for leg in legs
        ]
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(
            "OSRM route is missing geometry, distance, duration, or annotations"
        ) from exc

    for field in ("distance", "duration"):
        value = route[field]
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or value <= 0
        ):
            raise ValueError(
                f"OSRM route {field} must be a finite positive number"
            )

    if len(legs) != 1:
        raise ValueError(
            "Expected one OSRM leg for the requested origin and destination"
        )

    if not isinstance(coordinates, list) or not annotations:
        raise ValueError(
            "OSRM geometry and distance annotations must be lists"
        )

    if not isinstance(annotations[0], list):
        raise ValueError(
            "OSRM distance annotations must be a list"
        )

    segments = create_segments(coordinates, annotations[0])

    return {
        "distance_m": distance_m,
        "duration_s": duration_s,
        "geometry": route["geometry"],
        "segments": segments,
        "risk_assessment": "unavailable",
        "risk_data_gaps": [
            "Segment risk assessment has not yet been run"
        ],
    }

def assess_route_segments(
    db: Session,
    segments: list[dict[str, Any]],
    weather_by_segment: dict[int, dict[str, Any] | None] | None = None,
    traffic_by_segment: dict[int, dict[str, Any] | None] | None = None,
) -> list[dict[str, Any]]:
    """Match route segments to stored roads and assess available risk data."""
    weather_by_segment = weather_by_segment or {}
    traffic_by_segment = traffic_by_segment or {}
    assessed: list[dict[str, Any]] = []

    for segment in segments:
        start = segment["start"]
        end = segment["end"]
        weather = weather_by_segment.get(segment["segment_id"])
        traffic = traffic_by_segment.get(segment["segment_id"])
        heavy_traffic = (
            traffic["heavy_traffic"] if traffic is not None else None
        )

        segment_coordinates = segment.get(
            "coordinates",
            [start, end],
        )

        if len(segment_coordinates) < 2:
            raise ValueError(
                "A route segment must contain at least two coordinates"
            )

        # Build the full route segment geometry for spatial matching.
        coordinate_text = ", ".join(
            f"{float(lon)} {float(lat)}"
            for lon, lat in segment_coordinates
        )

        route_line = func.ST_GeomFromText(
            f"LINESTRING({coordinate_text})",
            4326,
        )

        route_geography = cast(
            route_line,
            Geography(srid=4326),
        )

        road_geography = cast(
            RoadSegment.geom,
            Geography(srid=4326),
        )

        distance = func.ST_Distance(
            road_geography,
            route_geography,
        )

        match = db.execute(
            select(
                RoadSegment,
                distance.label("distance_m"),
            )
            .where(
                func.ST_DWithin(
                    road_geography,
                    route_geography,
                    SEGMENT_MATCH_RADIUS_M,
                )
            )
            .order_by(distance)
            .limit(1)
        ).first()

        heavy_rain, low_visibility = classify_weather_risk(weather)

        # No stored road match means slope and database-backed risk
        # assessment cannot be completed for this segment.
        if match is None:
            gaps = [
                "No stored road segment matched within the configured radius",
                "Slope data unavailable for this segment",
            ]

            if traffic is None:
                gaps.append("Traffic data unavailable")
            if heavy_rain is None:
                gaps.append("Heavy-rain classification unavailable")

            if low_visibility is None:
                gaps.append("Low-visibility classification unavailable")

            assessed.append({
                **segment,
                "risk_status": "incomplete",
                "road_segment_id": None,
                "road_match_distance_m": None,
                "slope_percent": None,
                "risk_assessment": "incomplete",
                "weather_forecast": weather,
                "traffic": traffic,
                "data_sources": {
                    "weather": weather.get("source") if isinstance(weather, dict) else None,
                    "traffic": traffic.get("source") if traffic else None,
                },
                "score": None,
                "level": None,
                "color": None,
                "reasons": [],
                "risk_flags": None,
                "risk_data_gaps": sorted(set(gaps)),
            })
            continue

        road, distance_m = match

        # Assess database-backed and weather-backed risk flags.
        risk = assess_segment_risk(
            db,
            start,
            end,
            coordinates=segment_coordinates,
            slope_percent=road.slope_percent,
            slope_threshold_percent=SLOPE_THRESHOLD_PERCENT,
            heavy_rain=heavy_rain,
            heavy_traffic=heavy_traffic,
            low_visibility=low_visibility,
        )

        risk_data_gaps = list(risk["risk_data_gaps"])

        if heavy_rain is None:
            risk_data_gaps.append(
                "Heavy-rain classification unavailable"
            )

        if low_visibility is None:
            risk_data_gaps.append(
                "Low-visibility classification unavailable"
            )

        if road.slope_percent is None:
            risk_data_gaps.append(
                "Slope data unavailable for this segment"
            )

        if traffic is None:
            risk_data_gaps.append("Traffic data unavailable")

        level = risk["level"]

        assessed.append({
            **segment,
            "risk_status": risk["risk_assessment"],
            "road_segment_id": road.id,
            "road_match_distance_m": round(float(distance_m), 2),
            "slope_percent": road.slope_percent,
            "weather_forecast": weather,
            "traffic": traffic,
            "data_sources": {
                "weather": weather.get("source") if isinstance(weather, dict) else None,
                "traffic": traffic.get("source") if traffic else None,
            },
            "risk_assessment": risk["risk_assessment"],
            "risk_flags": risk["risk_flags"],
            "risk_data_gaps": sorted(set(risk_data_gaps)),
            "score": risk["score"],
            "level": level,
            "color": RISK_COLORS.get(level),
            "reasons": risk["reasons"],
        })

    return assessed


def calculate_overall_route_risk(
    segments: list[dict[str, Any]],
) -> dict[str, Any]:
    """Calculate complete or explicitly partial distance-weighted route risk."""
    incomplete_result = {
        "risk_assessment": "incomplete",
        "overall_risk_score": None,
        "overall_risk_level": None,
        "overall_risk_color": None,
        "overall_risk_reasons": [],
        "overall_risk_covered_distance_m": None,
        "overall_risk_coverage_percent": None,
    }

    if not isinstance(segments, list) or not segments:
        return incomplete_result

    total_distance = 0.0
    covered_distance = 0.0
    weighted_total = 0.0
    all_complete = True
    scored_segments = []

    for segment in segments:
        if not isinstance(segment, dict):
            return incomplete_result

        status = segment.get("risk_assessment")
        if status not in ("complete", "incomplete"):
            return incomplete_result

        if status != "complete":
            all_complete = False

        length = segment.get("length_m")
        if length is None or isinstance(length, bool):
            return incomplete_result

        try:
            length_value = float(length)
        except (TypeError, ValueError, OverflowError):
            return incomplete_result

        if not math.isfinite(length_value) or length_value < 0:
            return incomplete_result

        total_distance += length_value

        score = segment.get("score")
        if score is None:
            if status == "complete":
                return incomplete_result
            continue

        if isinstance(score, bool):
            return incomplete_result

        try:
            score_value = float(score)
        except (TypeError, ValueError, OverflowError):
            return incomplete_result

        if not math.isfinite(score_value) or not 0 <= score_value <= 100:
            return incomplete_result

        covered_distance += length_value
        weighted_total += score_value * length_value
        scored_segments.append(segment)

    if (
        not math.isfinite(total_distance)
        or total_distance <= 0
        or not math.isfinite(covered_distance)
        or covered_distance <= 0
        or not math.isfinite(weighted_total)
    ):
        return incomplete_result

    weighted_score = weighted_total / covered_distance
    if not math.isfinite(weighted_score):
        return incomplete_result

    weighted_score = max(0.0, min(100.0, weighted_score))

    reasons = sorted({
        reason
        for segment in scored_segments
        if isinstance(segment.get("reasons"), (list, tuple, set))
        for reason in segment["reasons"]
        if isinstance(reason, str)
    })

    coverage_percent = (covered_distance / total_distance) * 100.0

    if all_complete and len(scored_segments) == len(segments):
        overall_level = get_risk_level(weighted_score)
        return {
            "risk_assessment": "complete",
            "overall_risk_score": round(weighted_score, 2),
            "overall_risk_level": overall_level,
            "overall_risk_color": RISK_COLORS.get(overall_level, "green"),
            "overall_risk_reasons": reasons,
            "overall_risk_covered_distance_m": round(covered_distance, 2),
            "overall_risk_coverage_percent": 100.0,
        }

    return {
        "risk_assessment": "incomplete",
        "overall_risk_score": round(weighted_score, 2),
        "overall_risk_level": None,
        "overall_risk_color": None,
        "overall_risk_reasons": reasons,
        "overall_risk_covered_distance_m": round(covered_distance, 2),
        "overall_risk_coverage_percent": round(coverage_percent, 2),
    }
