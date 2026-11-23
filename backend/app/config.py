"""All tunable settings in one place. Values come from backend/.env (see .env.example)."""
import os

from dotenv import load_dotenv

load_dotenv()

# Path to the Firebase service account JSON (never commit this file).
SERVICE_ACCOUNT_PATH = os.getenv("SERVICE_ACCOUNT_PATH", "serviceAccountKey.json")

# --- Validation thresholds (used by app/rules.py) ---
# A GPS fix is only trusted if its reported accuracy is at most this many metres.
MAX_ACCURACY_M = float(os.getenv("MAX_ACCURACY_M", "30"))
# The fresh fix sent with /validate must be at most this old (seconds) by server time.
MAX_FIX_AGE_S = float(os.getenv("MAX_FIX_AGE_S", "120"))
# Allowed clock difference between phone and server (seconds) for "is this timestamp in the future?".
CLOCK_SKEW_S = float(os.getenv("CLOCK_SKEW_S", "30"))
# Average speed above this (m/s) over the whole quest is treated as implausible for walking/jogging.
MAX_AVG_SPEED_MPS = float(os.getenv("MAX_AVG_SPEED_MPS", "8"))
