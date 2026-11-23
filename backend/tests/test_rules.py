"""Core tests for the pure validation rules (app/rules.py)."""
from app.rules import progress_pct, validate_quest

NOW = 1_800_000_000_000          # fixed "server time" in ms
START = NOW - 20 * 60 * 1000     # quest started 20 minutes ago
CAFE = {"lat": 51.5136, "lng": -0.0985, "radiusM": 50}

RUN = {"id": "RUN-01", "active": True, "xp": 100, "requirements": {"distanceM": 1000, "steps": 1200}}
CAFE1 = {"id": "CAFE-01", "active": True, "xp": 80, "requirements": {"cafe": CAFE}}


def fix(lat=CAFE["lat"], lng=CAFE["lng"], acc=8, age_s=10, mocked=False):
    return {"lat": lat, "lng": lng, "accuracyM": acc, "timestamp": NOW - age_s * 1000, "isMocked": mocked}


def ongoing(pin=None):
    p = {"status": "ongoing", "startedAtMs": START}
    if pin:
        p["pin"] = pin
    return p


def run_evidence(distance=1100, steps=1300, **fix_kwargs):
    return {"distanceM": distance, "route": {"fixCount": 200, "rejectedCount": 5, "mockedCount": 0},
            "steps": {"count": steps, "windowStart": START, "windowEnd": NOW - 5000},
            "freshFix": fix(**fix_kwargs)}


def cafe_evidence(**fix_kwargs):
    return {"distanceM": 0, "route": {}, "steps": None, "freshFix": fix(**fix_kwargs)}


GOOD_PIN = fix(age_s=60)


# --- progress % ---
def test_progress_pct_spec_example():
    assert progress_pct(RUN["requirements"], 500, 600) == 50


def test_progress_pct_caps_and_cafe_binary():
    assert progress_pct(RUN["requirements"], 5000, 5000) == 100
    assert progress_pct(CAFE1["requirements"], cafe_ok=False) == 0
    assert progress_pct(CAFE1["requirements"], cafe_ok=True) == 100


# --- run quest ---
def test_run_pass():
    r = validate_quest(RUN, ongoing(), run_evidence(), NOW)
    assert r.passed, r.reasons


def test_run_insufficient_distance():
    r = validate_quest(RUN, ongoing(), run_evidence(distance=400), NOW)
    assert not r.passed and any("Distance" in m for m in r.reasons)


def test_run_insufficient_steps():
    r = validate_quest(RUN, ongoing(), run_evidence(steps=100), NOW)
    assert not r.passed and any("Steps" in m for m in r.reasons)


def test_stale_fix():
    r = validate_quest(RUN, ongoing(), run_evidence(age_s=600), NOW)
    assert not r.passed and any("stale" in m for m in r.reasons)


def test_poor_accuracy():
    r = validate_quest(RUN, ongoing(), run_evidence(acc=80), NOW)
    assert not r.passed and any("inaccurate" in m for m in r.reasons)


def test_mocked_location():
    r = validate_quest(RUN, ongoing(), run_evidence(mocked=True), NOW)
    assert not r.passed and any("Mock" in m for m in r.reasons)


def test_all_reasons_returned_together():
    r = validate_quest(RUN, ongoing(), run_evidence(distance=10, steps=10, acc=80), NOW)
    assert len(r.reasons) == 3 and len(r.remaining) == 2


# --- café quest ---
def test_cafe_pass():
    r = validate_quest(CAFE1, ongoing(pin=GOOD_PIN), cafe_evidence(), NOW)
    assert r.passed, r.reasons


def test_cafe_out_of_radius():
    far_lat = CAFE["lat"] + 0.002  # ~220 m north
    r = validate_quest(CAFE1, ongoing(pin=fix(lat=far_lat, age_s=60)), cafe_evidence(lat=far_lat), NOW)
    assert not r.passed and any("from the café" in m for m in r.reasons)


def test_cafe_without_pin_fails():
    r = validate_quest(CAFE1, ongoing(), cafe_evidence(), NOW)
    assert not r.passed and any("No confirmed pin" in m for m in r.reasons)


# --- state ---
def test_already_completed_gives_no_pass():
    r = validate_quest(RUN, {"status": "completed", "startedAtMs": START}, run_evidence(), NOW)
    assert not r.passed and r.already_completed


def test_not_started_fails():
    r = validate_quest(RUN, None, run_evidence(), NOW)
    assert not r.passed
