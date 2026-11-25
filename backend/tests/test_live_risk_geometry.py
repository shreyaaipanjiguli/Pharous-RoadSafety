from datetime import date, datetime, timezone

from backend.app.models.corridor import Corridor
from backend.app.models.incident import IncidentHistory
from backend.app.models.segment import RoadSegment
from backend.app.routers import routes as route_api


def test_live_risk_uses_complete_curved_road_geometry(
    client, db_session, monkeypatch
):
    corridor = db_session.query(Corridor).filter_by(id=1).first()
    assert corridor is not None, "Expected test corridor with ID 1"

    segment = RoadSegment(
        corridor_id=corridor.id,
        segment_no=987654321,
        geom=(
            "SRID=4326;"
            "LINESTRING(75.0 12.0, 75.01 12.01, 75.02 12.0)"
        ),
        length_m=2500.0,
        elevation_start_m=100.0,
        elevation_end_m=110.0,
        slope_percent=1.0,
    )
    db_session.add(segment)

    incident = IncidentHistory(
        external_id=(
            "curved-geometry-regression-"
            f"{datetime.now(timezone.utc).timestamp()}"
        ),
        incident_date=date.today(),
        type="landslide",
        location_name="Curved geometry regression test",
        geom="SRID=4326;POINT(75.01 12.01)",
        location_confidence="exact",
        source="automated regression test",
    )
    db_session.add(incident)
    db_session.flush()

    async def no_weather(*args, **kwargs):
        return None

    async def no_traffic(segments):
        return [None] * len(segments)

    monkeypatch.setattr(
        route_api, "_forecast_for_segment", no_weather
    )
    monkeypatch.setattr(
        route_api, "_fetch_traffic_for_segments", no_traffic
    )

    response = client.get(
        "/risk",
        params={"lat": 12.01, "lon": 75.01},
    )

    assert response.status_code == 200, response.text

    payload = response.json()
    matching = [
        item for item in payload["segments"]
        if item["road_segment_id"] == segment.id
    ]

    assert matching, "The curved test road was not selected"
    assert matching[0]["risk_flags"]["landslide_history"] is True
