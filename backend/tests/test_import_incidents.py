import pytest
import csv
from contextlib import contextmanager
from datetime import date

from geoalchemy2 import WKTElement
from sqlalchemy import func, select

from backend.app.models.incident import IncidentHistory
from backend.scripts import import_incidents


def write_csv(path, rows):
    headers = [
        "id", "date", "type", "location",
        "latitude", "longitude", "location_confidence", "source", "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def patch_importer(monkeypatch, db_session, csv_path):
    @contextmanager
    def session_scope():
        yield db_session

    monkeypatch.setattr(import_incidents, "DATA_FILE", csv_path)
    monkeypatch.setattr(import_incidents, "SessionLocal", session_scope)


def test_import_with_blank_coordinates_preserves_existing_location(
    tmp_path,
    monkeypatch,
    db_session,
):
    incident = IncidentHistory(
        external_id="IMPORT-PRESERVE-001",
        incident_date=date(2026, 10, 20),
        type="landslide",
        location_name="Original location",
        geom=WKTElement("POINT(75.6 12.8)", srid=4326),
        location_confidence="approximate",
        source="Original source",
        notes="Original notes",
    )
    db_session.add(incident)
    db_session.flush()

    csv_path = tmp_path / "incidents.csv"
    write_csv(csv_path, [{
        "id": "IMPORT-PRESERVE-001",
        "date": "2026-10-21",
        "type": "landslide",
        "location": "Updated location",
        "latitude": "",
        "longitude": "",
        "source": "Updated source",
        "notes": "Updated notes",
    }])

    patch_importer(monkeypatch, db_session, csv_path)
    import_incidents.import_incidents()

    db_session.refresh(incident)

    coordinates = db_session.execute(
        select(
            func.ST_X(IncidentHistory.geom),
            func.ST_Y(IncidentHistory.geom),
        ).where(IncidentHistory.id == incident.id)
    ).one()

    assert coordinates[0] == pytest.approx(75.6)
    assert coordinates[1] == pytest.approx(12.8)
    assert incident.location_confidence == "approximate"
    assert incident.location_name == "Updated location"


def test_import_new_incident_without_coordinates_stays_unknown(
    tmp_path,
    monkeypatch,
    db_session,
):
    csv_path = tmp_path / "incidents.csv"
    write_csv(csv_path, [{
        "id": "IMPORT-NEW-001",
        "date": "2026-10-21",
        "type": "landslide",
        "location": "Unlocated test site",
        "latitude": "",
        "longitude": "",
        "source": "Test source",
        "notes": "",
    }])

    patch_importer(monkeypatch, db_session, csv_path)
    import_incidents.import_incidents()

    incident = db_session.execute(
        select(IncidentHistory).where(
            IncidentHistory.external_id == "IMPORT-NEW-001"
        )
    ).scalar_one()

    assert incident.geom is None
    assert incident.location_confidence == "unknown"


@pytest.mark.parametrize(
    ("latitude", "longitude", "confidence", "error"),
    [
        ("12.8", "", "", "Both latitude and longitude"),
        ("91", "75.6", "", "Invalid coordinates"),
        ("12.8", "181", "", "Invalid coordinates"),
        ("NaN", "75.6", "", "Invalid coordinates"),
        ("12.8", "75.6", "unverified", "Invalid location confidence"),
    ],
)
def test_import_rejects_invalid_location_data(
    tmp_path,
    monkeypatch,
    db_session,
    latitude,
    longitude,
    confidence,
    error,
):
    csv_path = tmp_path / "incidents.csv"
    write_csv(csv_path, [{
        "id": "IMPORT-INVALID-001",
        "date": "2026-10-21",
        "type": "landslide",
        "location": "Invalid test site",
        "latitude": latitude,
        "longitude": longitude,
        "location_confidence": confidence,
        "source": "Test source",
        "notes": "",
    }])

    patch_importer(monkeypatch, db_session, csv_path)

    with pytest.raises(ValueError, match=error):
        import_incidents.import_incidents()
