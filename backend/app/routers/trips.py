import logging
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.trip import Trip
from ..schemas.trip import (
    TripEndRequest,
    TripResponse,
    TripStartRequest,
)
from ..schemas.trip_location import (
    TripLocationUpdate,
    TripLocationResponse,
)
from ..security.deps import get_current_user
from ..services.trip_alert_service import (
    check_trip_hazards,
)


logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/trips",
    tags=["trips"],
    responses={
        401: {"description": "Invalid or expired authentication token"},
        403: {"description": "User account is blocked"},
    },
)

DbSession = Annotated[Session, Depends(get_db)]

@router.get(
    "/active",
    response_model=TripResponse | None,
)
def get_active_trip(
    db: DbSession,
    current_user=Depends(get_current_user),
):
    return db.scalar(
        select(Trip).where(
            Trip.user_id == current_user.id,
            Trip.status == "active",
        )
    )



@router.post(
    "/start",
    response_model=TripResponse,
    status_code=status.HTTP_201_CREATED,
)
def start_trip(
    request: TripStartRequest,
    db: DbSession,
    current_user=Depends(get_current_user),
):
    active_trip = db.scalar(
        select(Trip).where(
            Trip.user_id == current_user.id,
            Trip.status == "active",
        )
    )

    if active_trip is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You already have an active trip.",
        )

    trip = Trip(
        user_id=current_user.id,
        route_json=request.route_json,
        status="active",
    )

    db.add(trip)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()

        original_error = getattr(exc, "orig", None)
        diagnostic = getattr(original_error, "diag", None)
        constraint_name = getattr(diagnostic, "constraint_name", None)

        if constraint_name == "uq_trips_one_active_per_user":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="You already have an active trip.",
            ) from exc

        raise

    db.refresh(trip)
    return trip


@router.post(
    "/{trip_id}/location",
    response_model=TripLocationResponse,
)
def update_trip_location(
    trip_id: int,
    request: TripLocationUpdate,
    db: DbSession,
    current_user=Depends(get_current_user),
):
    # Lock the active trip row to reduce duplicate alerts
    # when concurrent location updates arrive.
    trip = db.scalar(
        select(Trip)
        .where(
            Trip.id == trip_id,
            Trip.user_id == current_user.id,
        )
        .with_for_update()
    )

    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found.",
        )

    if trip.status != "active":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Trip is not active.",
        )

    trip.last_latitude = request.latitude
    trip.last_longitude = request.longitude
    trip.last_location_at = datetime.now(timezone.utc).replace(tzinfo=None)

    alerts_sent = check_trip_hazards(db, trip)

    db.commit()

    return TripLocationResponse(
        message="Location updated successfully.",
        trip_id=trip.id,
        alerts_sent=alerts_sent,
    )


@router.post("/{trip_id}/end", response_model=TripResponse)
def end_trip(
    trip_id: int,
    request: TripEndRequest,
    db: DbSession,
    current_user=Depends(get_current_user),
):
    trip = db.scalar(
        select(Trip)
        .where(
            Trip.id == trip_id,
            Trip.user_id == current_user.id,
        )
        .with_for_update()
    )

    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found.",
        )

    if trip.status != "active":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Trip has already ended.",
        )

    trip.status = request.status
    trip.ended_at = datetime.now(timezone.utc).replace(tzinfo=None)

    db.commit()
    db.refresh(trip)

    return trip

