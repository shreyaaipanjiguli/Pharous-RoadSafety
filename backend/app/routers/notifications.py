from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, func, update
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.notification import Notification
from ..models.user import User
from ..schemas.notification import (
    NotificationListResponse,
    NotificationResponse,
    UnreadCountResponse,
    NotificationActionResponse,
)
from ..security.deps import get_current_user


router = APIRouter(prefix="/notifications", tags=["notifications"])

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=NotificationListResponse)
def get_notifications(
    db: DbSession,
    current_user: CurrentUser,
    limit: int = 50,
    offset: int = 0,
):
    if not 1 <= limit <= 100 or offset < 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid pagination parameters.",
        )

    notifications = db.scalars(
        select(Notification)
        .where(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()

    unread_count = db.scalar(
        select(func.count(Notification.id)).where(
            Notification.user_id == current_user.id,
            Notification.is_read.is_(False),
        )
    ) or 0

    return {
        "notifications": notifications,
        "unread_count": unread_count,
    }


@router.get("/unread-count", response_model=UnreadCountResponse)
def get_unread_count(
    db: DbSession,
    current_user: CurrentUser,
):
    count = db.scalar(
        select(func.count(Notification.id)).where(
            Notification.user_id == current_user.id,
            Notification.is_read.is_(False),
        )
    ) or 0

    return {"unread_count": count}


@router.patch(
    "/read-all",
    response_model=NotificationActionResponse,
)
def mark_all_notifications_read(
    db: DbSession,
    current_user: CurrentUser,
):
    db.execute(
        update(Notification)
        .where(
            Notification.user_id == current_user.id,
            Notification.is_read.is_(False),
        )
        .values(is_read=True)
    )
    db.commit()

    return {"message": "All notifications marked as read."}


@router.patch(
    "/{notification_id}/read",
    response_model=NotificationActionResponse,
)
def mark_notification_read(
    notification_id: int,
    db: DbSession,
    current_user: CurrentUser,
):
    notification = db.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == current_user.id,
        )
    )

    if notification is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found.",
        )

    notification.is_read = True
    db.commit()

    return {"message": "Notification marked as read."}
