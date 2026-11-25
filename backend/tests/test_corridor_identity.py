from backend.app.models.corridor import Corridor
from backend.app.models.segment import RoadSegment


def test_same_segment_number_is_allowed_in_different_corridors(db_session):
    shiradi = db_session.query(Corridor).filter_by(
        name="Shiradi Ghat"
    ).one()

    second_corridor = Corridor(
        name="Test Highway",
        highway_code="TEST-01",
    )
    db_session.add(second_corridor)
    db_session.flush()

    first_segment = RoadSegment(
        corridor_id=shiradi.id,
        segment_no=1,
        geom="SRID=4326;LINESTRING(75.0 12.0, 75.01 12.0)",
        length_m=1000.0,
        elevation_start_m=100.0,
        elevation_end_m=102.0,
        slope_percent=0.2,
    )
    second_segment = RoadSegment(
        corridor_id=second_corridor.id,
        segment_no=1,
        geom="SRID=4326;LINESTRING(76.0 13.0, 76.01 13.0)",
        length_m=1000.0,
        elevation_start_m=200.0,
        elevation_end_m=202.0,
        slope_percent=0.2,
    )

    db_session.add_all([first_segment, second_segment])
    db_session.flush()

    assert first_segment.id != second_segment.id
    assert first_segment.segment_no == second_segment.segment_no
    assert first_segment.corridor_id != second_segment.corridor_id
