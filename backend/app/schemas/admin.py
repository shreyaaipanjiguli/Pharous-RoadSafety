from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class UserBlockRequest(BaseModel):
    is_blocked: bool


class IncidentUpdateRequest(BaseModel):
    type: str | None = Field(default=None, min_length=1, max_length=50)
    incident_date: date | None = None
    location_name: str | None = Field(default=None, min_length=1, max_length=200)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    location_confidence: Literal["exact", "approximate", "unknown"] | None = None
    source: str | None = Field(default=None, min_length=1, max_length=500)
    notes: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_coordinates(self):
        coordinates_provided = (
            "latitude" in self.model_fields_set
            or "longitude" in self.model_fields_set
        )

        if (self.latitude is None) != (self.longitude is None):
            raise ValueError(
                "latitude and longitude must be provided together"
            )

        if self.latitude is not None:
            if self.location_confidence not in ("exact", "approximate"):
                raise ValueError(
                    "location_confidence must be exact or approximate "
                    "when coordinates are provided"
                )
        elif coordinates_provided:
            if self.location_confidence not in (None, "unknown"):
                raise ValueError(
                    "Cleared coordinates must have unknown confidence"
                )
        elif self.location_confidence is not None:
            raise ValueError(
                "location_confidence can only be changed when coordinates "
                "are provided or cleared"
            )

        return self


class AdminStatsResponse(BaseModel):
    total_users: int
    blocked_users: int
    total_reports: int
    active_reports: int
    cleared_reports: int
    rejected_reports: int
    active_hazards: int
    reports_by_type: dict[str, int]
    reports_by_status: dict[str, int]
    reports_by_day: dict[str, int]