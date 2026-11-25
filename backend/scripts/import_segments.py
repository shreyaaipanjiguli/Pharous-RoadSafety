import argparse
import json
from pathlib import Path

from sqlalchemy.dialects.postgresql import insert

from backend.app.database import SessionLocal
from backend.app.models.corridor import Corridor
from backend.app.models.segment import RoadSegment


DATA_FILE = (
    Path(__file__).resolve().parents[2]
    / "data"
    / "route_segments_with_slope.json"
)


def import_segments(corridor_id: int) -> None:
    with DATA_FILE.open("r", encoding="utf-8") as file:
        segments = json.load(file)

    imported = 0

    with SessionLocal() as session:
        corridor = session.get(Corridor, corridor_id)
        if corridor is None:
            raise ValueError(f"Corridor ID {corridor_id} does not exist.")

        for item in segments:
            start_lon, start_lat = item["start"]
            end_lon, end_lat = item["end"]

            values = {
                "corridor_id": corridor_id,
                "segment_no": item["segment_id"],
                "geom": (
                    f"SRID=4326;LINESTRING("
                    f"{start_lon} {start_lat}, "
                    f"{end_lon} {end_lat})"
                ),
                "length_m": item["length_m"],
                "elevation_start_m": item["elevation_start_m"],
                "elevation_end_m": item["elevation_end_m"],
                "slope_percent": item["slope_percent"],
            }

            statement = insert(RoadSegment).values(**values)
            statement = statement.on_conflict_do_update(
                index_elements=[
                    RoadSegment.corridor_id,
                    RoadSegment.segment_no,
                ],
                set_={
                    "geom": statement.excluded.geom,
                    "length_m": statement.excluded.length_m,
                    "elevation_start_m": statement.excluded.elevation_start_m,
                    "elevation_end_m": statement.excluded.elevation_end_m,
                    "slope_percent": statement.excluded.slope_percent,
                },
            )

            session.execute(statement)
            imported += 1

        session.commit()

    print(
        f"Imported or updated {imported} segments "
        f"for corridor '{corridor.name}' (ID: {corridor_id})."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--corridor-id",
        type=int,
        required=True,
        help="ID of the corridor receiving these segments",
    )
    args = parser.parse_args()
    import_segments(args.corridor_id)
