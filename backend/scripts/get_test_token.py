"""Dev helper: signs in a NEW anonymous Firebase user and prints its ID token (valid ~1 hour).

Needs FIREBASE_WEB_API_KEY in backend/.env (Firebase console -> Project settings -> General).
Usage:  python scripts/get_test_token.py
"""
import os
import sys

import requests
from dotenv import load_dotenv

load_dotenv()
key = os.getenv("FIREBASE_WEB_API_KEY")
if not key:
    sys.exit("Set FIREBASE_WEB_API_KEY in backend/.env")

r = requests.post(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
                  json={"returnSecureToken": True}, timeout=15)
if r.status_code != 200:
    sys.exit(f"Sign-in failed ({r.status_code}): {r.text}\nIs Anonymous auth enabled in the Firebase console?")
data = r.json()
print(f"uid: {data['localId']}", file=sys.stderr)
print(data["idToken"])
