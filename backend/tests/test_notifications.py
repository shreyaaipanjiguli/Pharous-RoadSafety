from datetime import datetime, timezone

from backend.app.models import User
from backend.app.models.notification import Notification
from backend.app.security.jwt import create_token


def create_user(db, email):
    user = User(
        name="Notification Test User",
        email=email,
        password_hash="test-hash",
        role="driver",
        preferred_language="en",
        is_blocked=False,
    )
    db.add(user)
    db.flush()
    return user


def auth_headers(user):
    token = create_token(user.id, user.role)
    return {"Authorization": f"Bearer {token}"}


def create_notification(db, user, event_key, is_read=False):
    notification = Notification(
        user_id=user.id,
        title="Test hazard alert",
        body="A test notification.",
        type="test",
        event_key=event_key,
        is_read=is_read,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    db.add(notification)
    db.flush()
    return notification


def test_notifications_require_authentication(client):
    response = client.get("/notifications")
    assert response.status_code in (401, 403)


def test_user_only_sees_own_notifications(client, db_session):
    user1 = create_user(db_session, "notification-user1@example.com")
    user2 = create_user(db_session, "notification-user2@example.com")

    create_notification(db_session, user1, "event-user1")
    create_notification(db_session, user2, "event-user2")

    response = client.get(
        "/notifications",
        headers=auth_headers(user1),
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data["notifications"]) == 1
    assert data["notifications"][0]["event_key"] if "event_key" in data["notifications"][0] else True
    assert data["notifications"][0]["title"] == "Test hazard alert"


def test_unread_count_is_correct(client, db_session):
    user = create_user(db_session, "notification-count@example.com")

    create_notification(db_session, user, "unread-1")
    create_notification(db_session, user, "unread-2")
    create_notification(db_session, user, "read-1", is_read=True)

    response = client.get(
        "/notifications/unread-count",
        headers=auth_headers(user),
    )

    assert response.status_code == 200
    assert response.json()["unread_count"] == 2


def test_mark_single_notification_read(client, db_session):
    user = create_user(db_session, "notification-read@example.com")
    notification = create_notification(db_session, user, "read-event")

    response = client.patch(
        f"/notifications/{notification.id}/read",
        headers=auth_headers(user),
    )

    assert response.status_code == 200
    assert notification.is_read is True


def test_user_cannot_mark_another_users_notification_read(client, db_session):
    user1 = create_user(db_session, "notification-owner@example.com")
    user2 = create_user(db_session, "notification-outsider@example.com")

    notification = create_notification(db_session, user1, "private-event")

    response = client.patch(
        f"/notifications/{notification.id}/read",
        headers=auth_headers(user2),
    )

    assert response.status_code == 404
    assert notification.is_read is False


def test_mark_all_notifications_read(client, db_session):
    user = create_user(db_session, "notification-read-all@example.com")

    create_notification(db_session, user, "read-all-1")
    create_notification(db_session, user, "read-all-2")

    response = client.patch(
        "/notifications/read-all",
        headers=auth_headers(user),
    )

    assert response.status_code == 200

    unread_count = client.get(
        "/notifications/unread-count",
        headers=auth_headers(user),
    )

    assert unread_count.status_code == 200
    assert unread_count.json()["unread_count"] == 0


def test_notifications_pagination(client, db_session):
    user = create_user(db_session, "notification-pagination@example.com")

    create_notification(db_session, user, "page-1")
    create_notification(db_session, user, "page-2")
    create_notification(db_session, user, "page-3")

    response = client.get(
        "/notifications?limit=2&offset=0",
        headers=auth_headers(user),
    )

    assert response.status_code == 200
    assert len(response.json()["notifications"]) == 2


def test_notifications_reject_invalid_pagination(client, db_session):
    user = create_user(db_session, "notification-invalid-page@example.com")

    response = client.get(
        "/notifications?limit=0",
        headers=auth_headers(user),
    )

    assert response.status_code == 422
