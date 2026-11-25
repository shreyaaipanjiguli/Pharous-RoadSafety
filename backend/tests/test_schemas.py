
import pytest
from pydantic import ValidationError

from backend.app.schemas.report import ReportCreate, ReportVoteCreate
from backend.app.schemas.route import Coordinate


def test_report_rejects_invalid_severity():
    with pytest.raises(ValidationError):
        ReportCreate(
            type="landslide",
            severity=4,
            latitude=12.85,
            longitude=75.65,
        )


def test_vote_rejects_invalid_value():
    with pytest.raises(ValidationError):
        ReportVoteCreate(vote="maybe")


def test_coordinate_rejects_invalid_latitude():
    with pytest.raises(ValidationError):
        Coordinate(latitude=91, longitude=75.65)


def test_report_rejects_description_over_500_characters():
    with pytest.raises(ValidationError):
        ReportCreate(
            type="landslide",
            severity=2,
            description="x" * 501,
            latitude=12.85,
            longitude=75.65,
        )


def test_protected_endpoints_document_auth_responses(client):
    response = client.get("/openapi.json")
    assert response.status_code == 200
    spec = response.json()
    paths = spec.get("paths", {})

    # Check protected user/driver endpoints
    for path, method in [
        ("/user/profile", "put"),
        ("/devices", "post"),
        ("/reports", "post"),
        ("/trips/start", "post"),
    ]:
        responses = paths[path][method]["responses"]
        assert "401" in responses, f"Missing 401 in {method.upper()} {path}"
        assert "403" in responses, f"Missing 403 in {method.upper()} {path}"

    # Check admin endpoints
    for path, method in [
        ("/admin/stats", "get"),
        ("/admin/reports/suspicious", "get"),
    ]:
        responses = paths[path][method]["responses"]
        assert "401" in responses, f"Missing 401 in {method.upper()} {path}"
        assert "403" in responses, f"Missing 403 in {method.upper()} {path}"
