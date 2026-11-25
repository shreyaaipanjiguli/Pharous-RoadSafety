import hashlib
import math
from datetime import datetime, timedelta, timezone

from geoalchemy2 import Geography
from sqlalchemy import cast, func, or_, select
from sqlalchemy.orm import Session

from ..integrations.fcm import send
from ..models.device import DeviceToken
from ..models.report import Report
from ..models.trip import Trip
from ..models.notification_outbox import NotificationOutbox
from ..models.notification import Notification



ALERT_RADIUS_M = 500.0
ALERTABLE_TYPES = ("landslide", "falling_rock")



def check_trip_hazards(
    db: Session,
    trip: Trip,
    upcoming_segments: list[dict] | None = None,
    report_id: int | None = None,
) -> int:
    """
    Find severe active hazards near upcoming route segments.
    Falls back to the latest GPS location when no route is supplied.
    Persist one inbox event per user/report and queue each registered device.
    """

    report_geography = cast(
        Report.geom,
        Geography(srid=4326),
    )

    hazard_conditions = []

    if upcoming_segments:
        for segment in upcoming_segments:
            coordinates = segment.get("coordinates", [])

            if not isinstance(coordinates, list) or len(coordinates) < 2:
                continue

            valid_coordinates = []

            for coordinate in coordinates:
                try:
                    lon, lat = float(coordinate[0]), float(coordinate[1])
                except (TypeError, ValueError, IndexError):
                    continue

                if not (math.isfinite(lon) and math.isfinite(lat)):
                    continue

                if not (-180 <= lon <= 180 and -90 <= lat <= 90):
                    continue

                valid_coordinates.append((lon, lat))

            if len(valid_coordinates) < 2:
                continue

            wkt_coordinates = ", ".join(
                f"{lon} {lat}" for lon, lat in valid_coordinates
            )
            line_wkt = f"LINESTRING({wkt_coordinates})"

            route_line = func.ST_GeomFromText(line_wkt, 4326)
            route_geography = cast(
                route_line,
                Geography(srid=4326),
            )

            hazard_conditions.append(
                func.ST_DWithin(
                    report_geography,
                    route_geography,
                    ALERT_RADIUS_M,
                )
            )

    # Backward-compatible fallback for callers without route segments.
    if not hazard_conditions:
        if trip.last_latitude is None or trip.last_longitude is None:
            return 0

        point = func.ST_SetSRID(
            func.ST_MakePoint(
                trip.last_longitude,
                trip.last_latitude,
            ),
            4326,
        )

        point_geography = cast(
            point,
            Geography(srid=4326),
        )

        hazard_conditions.append(
            func.ST_DWithin(
                report_geography,
                point_geography,
                ALERT_RADIUS_M,
            )
        )

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    report_query = select(Report).where(
        Report.status == "active",
        Report.type.in_(ALERTABLE_TYPES),
        Report.severity >= 2,
        or_(
            Report.expires_at.is_(None),
            Report.expires_at > now,
        ),
        Report.geom.is_not(None),
        or_(*hazard_conditions),
    )

    if report_id is not None:
        report_query = report_query.where(Report.id == report_id)

    reports = db.scalars(report_query).all()

    already_alerted = set(trip.alerted_report_ids or [])

    new_reports = [
        report
        for report in reports
        if report.id not in already_alerted
        and report.user_id != trip.user_id
    ]

    if not new_reports:
        return 0

    tokens = db.scalars(
        select(DeviceToken.fcm_token).where(
            DeviceToken.user_id == trip.user_id
        )
    ).all()

    queued_reports = 0

    for report in new_reports:
        title = "Hazard ahead"
        body = (
            f"{report.type.replace('_', ' ').title()} reported "
            "within 500 metres of your upcoming route. "
            "Please proceed carefully."
        )

        event_key = f"hazard:report:{report.id}"

        notification = db.scalar(
            select(Notification).where(
                Notification.user_id == trip.user_id,
                Notification.event_key == event_key,
            )
        )

        if notification is None:
            notification = Notification(
                user_id=trip.user_id,
                trip_id=trip.id,
                title=title,
                body=body,
                type="hazard",
                event_key=event_key,
            )
            db.add(notification)
            db.flush()

        for token in tokens:
            db.add(
                NotificationOutbox(
                    user_id=trip.user_id,
                    notification_id=notification.id,
                    trip_id=trip.id,
                    dedupe_key=(
                        f"hazard:{trip.id}:{report.id}:"
                        f"{hashlib.sha256(token.encode()).hexdigest()}"
                    ),
                    fcm_token=token,
                    title=title,
                    body=body,
                )
            )

        already_alerted.add(report.id)
        queued_reports += 1

    trip.alerted_report_ids = sorted(already_alerted)
    db.flush()
    return queued_reports


RISK_LEVEL_ORDER = {
    "Green": 0,
    "Yellow": 1,
    "Orange": 2,
    "Red": 3,
}



def check_trip_risk_escalation(
    db: Session,
    trip: Trip,
    current_level: str | None,
) -> bool:
    """Notify when a complete risk assessment shows an upward transition."""

    if current_level not in RISK_LEVEL_ORDER:
        return False

    previous_level = trip.last_alerted_level

    if previous_level not in RISK_LEVEL_ORDER:
        previous_level = "Green"

    current_rank = RISK_LEVEL_ORDER[current_level]
    previous_rank = RISK_LEVEL_ORDER[previous_level]

    # Update the baseline on downgrade without sending an alert.
    if current_rank < previous_rank:
        trip.last_alerted_level = current_level
        return False

    if current_rank == previous_rank:
        return False

    tokens = db.scalars(
        select(DeviceToken.fcm_token).where(
            DeviceToken.user_id == trip.user_id
        )
    ).all()

    if not tokens:
        return False

    title = f"Route risk increased to {current_level}"
    body = (
        f"Risk on your selected route has increased "
        f"from {previous_level} to {current_level}. "
        "Please proceed carefully."
    )

    for token in tokens:
        db.add(
            NotificationOutbox(
                user_id=trip.user_id,
                trip_id=trip.id,
                dedupe_key=(
                    f"risk:{trip.id}:{previous_level}:{current_level}:"
                    f"{datetime.now(timezone.utc).replace(tzinfo=None).isoformat()}:"
                    f"{hashlib.sha256(token.encode()).hexdigest()}"
                ),
                fcm_token=token,
                title=title,
                body=body,
            )
        )

    # The outbox records the notification durably in this transaction.
    trip.last_alerted_level = current_level
    db.flush()
    return True


MAX_NOTIFICATION_ATTEMPTS = 5


def deliver_pending_notifications(
    db: Session,
    limit: int = 100,
) -> int:
    """Deliver committed outbox rows without holding trip-row locks."""
    from ..integrations.fcm import send

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    pending = db.scalars(
        select(NotificationOutbox)
        .where(
            NotificationOutbox.status == "pending",
            NotificationOutbox.next_attempt_at <= now,
        )
        .order_by(NotificationOutbox.id)
        .limit(limit)
        .with_for_update(skip_locked=True)
    ).all()

    delivered = 0

    for item in pending:
        try:
            success = send(item.fcm_token, item.title, item.body)
        except Exception:
            success = False

        if success:
            item.status = "sent"
            item.sent_at = datetime.now(timezone.utc).replace(tzinfo=None)
            item.last_error = None
            delivered += 1
        else:
            item.attempts += 1

            if item.attempts >= MAX_NOTIFICATION_ATTEMPTS:
                item.status = "failed"
                item.last_error = (
                    "FCM delivery failed after maximum attempts"
                )
            else:
                delay_seconds = min(
                    3600,
                    30 * (2 ** min(item.attempts - 1, 7)),
                )
                item.next_attempt_at = (
                    datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=delay_seconds)
                )
                item.last_error = "FCM delivery failed"

    db.commit()
    return delivered
