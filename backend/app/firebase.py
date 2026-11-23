"""Initialises the Firebase Admin SDK once and hands out the Firestore client."""
import firebase_admin
from firebase_admin import credentials, firestore

from app import config

_db = None


def init_firebase() -> None:
    if not firebase_admin._apps:
        cred = credentials.Certificate(config.SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)


def get_db():
    """Firestore client (created on first use)."""
    global _db
    if _db is None:
        init_firebase()
        _db = firestore.client()
    return _db
