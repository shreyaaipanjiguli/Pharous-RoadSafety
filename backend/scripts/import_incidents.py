import math

import csv
from datetime import date
from pathlib import Path

from geoalchemy2 import WKTElement
from sqlalchemy import case, func
from sqlalchemy.dialects.postgresql import insert

from backend.app.database import SessionLocal
from backend.app.models.incident import IncidentHistory


DATA_FILE = Path(__file__).resolve().parents[2] / "data" / "incidents.csv"


def import_incidents() -> None:
    imported = 0
    without_coordinates = 0

    with DATA_FILE.open("r", encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)

        with SessionLocal() as session:
            for row in reader:
                external_id = row["id"].strip()

                if not external_id:
                    raise ValueError("Incident row has no ID.")

                latitude_text = (row.get("latitude") or "").strip()
                longitude_text = (row.get("longitude") or "").strip()
                confidence_text = (
                    row.get("location_confidence") or ""
                ).strip().lower()

                if confidence_text not in {"", "exact", "approximate", "unknown"}:
                    raise ValueError(
                        f"Invalid location confidence for {external_id}: {confidence_text}"
                    )

                geom = None
                location_confidence = confidence_text or "unknown"

                if bool(latitude_text) != bool(longitude_text):
                    raise ValueError(
                        f"Both latitude and longitude are required for {external_id}."
                    )

                if latitude_text and longitude_text:
                    latitude = float(latitude_text)
                    longitude = float(longitude_text)

                    if (
                        not math.isfinite(latitude)
                        or not math.isfinite(longitude)
                        or not -90 <= latitude <= 90
                        or not -180 <= longitude <= 180
                    ):
                        raise ValueError(f"Invalid coordinates for {external_id}.")

                    geom = WKTElement(
                        f"POINT({longitude} {latitude})",
                        srid=4326,
                    )
                else:
                    without_coordinates += 1
                    location_confidence = "unknown"

                values = {
                    "external_id": external_id,
                    "incident_date": date.fromisoformat(
                        row["date"].strip()
                    ),
                    "type": row["type"].strip(),
                    "location_name": row["location"].strip(),
                    "geom": geom,
                    "location_confidence": location_confidence,
                    "source": row["source"].strip(),
                    "notes": row.get("notes", "").strip() or None,
                }

                statement = insert(IncidentHistory).values(**values)

                statement = statement.on_conflict_do_update(
                    index_elements=[IncidentHistory.external_id],
                    set_={
                        "incident_date": statement.excluded.incident_date,
                        "type": statement.excluded.type,
                        "location_name": statement.excluded.location_name,
                        "geom": func.coalesce(
                            statement.excluded.geom,
                            IncidentHistory.geom,
                        ),
                        "location_confidence": case(
                            (
                                statement.excluded.geom.is_not(None),
                                statement.excluded.location_confidence,
                            ),
                            else_=IncidentHistory.location_confidence,
                        ),
                        "source": statement.excluded.source,
                        "notes": statement.excluded.notes,
                    },
                )

                session.execute(statement)
                imported += 1

            session.commit()

    print(
        f"{imported} imported or updated; "
        f"{without_coordinates} without coordinates."
    )


if __name__ == "__main__":
    import_incidents()
