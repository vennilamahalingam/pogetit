"""Writes the four quest definitions to Firestore. Safe to run repeatedly (overwrites by ID).

Usage (from backend/ with the venv active):
    python seed.py
    python seed.py --cafe1 51.5136,-0.0985 --cafe2 51.5079,-0.0877 --radius 50

--cafe1 is the café for CAFE-01, --cafe2 for CAFE-02. Use this to put in
reviewer-chosen coordinates. All targets and XP live here as data, not in app code.
"""
import argparse

from app.firebase import get_db

# Default test cafés (placeholders in central London) - replace with --cafe1/--cafe2.
DEFAULT_CAFE1 = (51.513600, -0.098500)  # near St Paul's
DEFAULT_CAFE2 = (51.507900, -0.087700)  # near London Bridge


def parse_latlng(text: str) -> tuple[float, float]:
    lat, lng = (float(x) for x in text.split(","))
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        raise argparse.ArgumentTypeError(f"Out of range: {text}")
    return lat, lng


def build_quests(cafe1, cafe2, radius_m: float) -> list[dict]:
    return [
        {
            "id": "RUN-01", "title": "Beginner Jog", "type": "run",
            "description": "Jog 1 km with GPS tracking on.",
            "requirements": {"distanceM": 1000, "steps": 1200},
            "xp": 100, "active": True,
        },
        {
            "id": "RUN-02", "title": "Step-Up Run", "type": "run",
            "description": "Run 2 km with GPS tracking on.",
            "requirements": {"distanceM": 2000, "steps": 2500},
            "xp": 150, "active": True,
        },
        {
            "id": "CAFE-01", "title": "Local Café Stop", "type": "cafe",
            "description": "Go to the café and confirm your location there.",
            "requirements": {"cafe": {"lat": cafe1[0], "lng": cafe1[1], "radiusM": radius_m}},
            "xp": 80, "active": True,
        },
        {
            "id": "CAFE-02", "title": "Walk for Your Coffee", "type": "cafe",
            "description": "Walk at least 500 m, then confirm your location at the café.",
            # steps target for CAFE-02 is not fixed by the spec; 600 is an assumption (~1.2 steps/m).
            "requirements": {
                "distanceM": 500, "steps": 600,
                "cafe": {"lat": cafe2[0], "lng": cafe2[1], "radiusM": radius_m},
            },
            "xp": 120, "active": True,
        },
    ]


def main() -> None:
    p = argparse.ArgumentParser(description="Seed PoGetIt quests into Firestore.")
    p.add_argument("--cafe1", type=parse_latlng, default=DEFAULT_CAFE1, help="lat,lng for CAFE-01")
    p.add_argument("--cafe2", type=parse_latlng, default=DEFAULT_CAFE2, help="lat,lng for CAFE-02")
    p.add_argument("--radius", type=float, default=50, help="café geofence radius in metres")
    args = p.parse_args()

    db = get_db()
    for q in build_quests(args.cafe1, args.cafe2, args.radius):
        db.collection("quests").document(q["id"]).set(q)
        print(f"seeded {q['id']}: {q['requirements']}")


if __name__ == "__main__":
    main()
