
import pytest

from risk_engine.incident_data import load_incidents


def test_loads_all_twelve_incidents():
    incidents = load_incidents()

    assert len(incidents) == 12


def test_incident_ids_are_unique():
    incidents = load_incidents()
    ids = [incident["id"] for incident in incidents]

    assert len(ids) == len(set(ids))


def test_all_incidents_have_supported_hazard_types():
    incidents = load_incidents()

    supported_types = {
        "landslide",
        "falling_tree",
        "falling_rock",
        "flood",
    }

    assert {incident["type"] for incident in incidents} == supported_types


def test_missing_coordinates_are_none():
    incidents = load_incidents()

    assert all(
        incident["latitude"] is None
        and incident["longitude"] is None
        for incident in incidents
    )


def test_incident_dates_are_valid_iso_dates():
    from datetime import date

    incidents = load_incidents()

    for incident in incidents:
        assert date.fromisoformat(incident["date"])


def test_incidents_have_sources_and_notes():
    incidents = load_incidents()

    assert all(incident["source"] for incident in incidents)
    assert all(incident["notes"] for incident in incidents)
