"""Firebase ID token check. Every protected route depends on `get_current_uid`.

The uid always comes from the verified token, never from the request body,
so a user can only ever act on their own progress and XP.
"""
from fastapi import Header, HTTPException
from firebase_admin import auth

from app.firebase import init_firebase


def get_current_uid(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing 'Authorization: Bearer <Firebase ID token>' header.")
    token = authorization.removeprefix("Bearer ").strip()
    init_firebase()
    try:
        decoded = auth.verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token. Sign in again.")
    return decoded["uid"]
