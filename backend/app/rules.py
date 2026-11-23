"""Quest rules as pure functions: no Firestore, no clock, no network.

Everything is passed in (quest dict, progress dict, evidence dict, server time),
so each rule can be unit tested directly. All timestamps are epoch milliseconds (int).

Shapes used here:
  quest     = {"id", "active", "requirements": {"distanceM"?, "steps"?, "cafe"?: {"lat","lng","radiusM"}}, "xp"}
  progress  = {"status", "startedAtMs", "pin"?: {"lat","lng","accuracyM","timestamp","isMocked"}} or None
  evidence  = {"distanceM", "route": {"fixCount","rejectedCount","mockedCount"},
               "steps": {"count","windowStart","windowEnd"} or None,
               "freshFix": {"lat","lng","accuracyM","timestamp","isMocked"}}
"""
import math
from dataclasses import dataclass, field

from app import config

EARTH_RADIUS_M = 6_371_000


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in metres between two lat/lng points."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def progress_pct(requirements: dict, distance_m: float = 0, steps: int = 0, cafe_ok: bool = False) -> int:
    """Average of each requirement's capped ratio, x100, rounded to an integer.

    Example: 500/1000 m and 600/1200 steps -> (0.5 + 0.5) / 2 -> 50.
    Café check-in is binary (0 or 1).
    """
    ratios = []
    if requirements.get("distanceM"):
        ratios.append(min(distance_m / requirements["distanceM"], 1.0))
    if requirements.get("steps"):
        ratios.append(min(steps / requirements["steps"], 1.0))
    if requirements.get("cafe"):
        ratios.append(1.0 if cafe_ok else 0.0)
    if not ratios:
        return 0
    return math.floor(sum(ratios) / len(ratios) * 100 + 0.5)  # round half up (Python's round() is banker's)


def pin_inside_cafe(requirements: dict, pin: dict | None) -> bool:
    """Informational only (for progress %): is the saved pin inside the café radius?"""
    cafe = requirements.get("cafe")
    if not cafe or not pin:
        return False
    return haversine_m(pin["lat"], pin["lng"], cafe["lat"], cafe["lng"]) <= cafe["radiusM"]


@dataclass
class ValidationResult:
    passed: bool
    reasons: list[str] = field(default_factory=list)      # readable failure messages
    remaining: list[dict] = field(default_factory=list)   # what is still missing, for the app to show
    already_completed: bool = False


def validate_quest(quest: dict | None, progress: dict | None, evidence: dict, now_ms: int,
                   cfg=config) -> ValidationResult:
    """Run every check in order and collect ALL failing reasons."""
    # 1. Quest exists, is active, user is on it. These stop early: other checks would be meaningless.
    if quest is None:
        return ValidationResult(False, ["Quest not found."])
    if not quest.get("active", False):
        return ValidationResult(False, ["This quest is not active."])
    status = (progress or {}).get("status", "available")
    if status == "completed":
        return ValidationResult(False, ["Quest already completed. XP was already awarded."], already_completed=True)
    if status != "ongoing":
        return ValidationResult(False, ["Quest has not been started. Tap Accept/Start first."])

    req = quest.get("requirements", {})
    reasons: list[str] = []
    remaining: list[dict] = []
    fix = evidence["freshFix"]
    route = evidence.get("route") or {}
    steps_ev = evidence.get("steps")
    started = progress["startedAtMs"]
    skew_ms = cfg.CLOCK_SKEW_S * 1000

    def in_window(ts: int) -> bool:
        return started - skew_ms <= ts <= now_ms + skew_ms

    # 2. Time window: server time after start; evidence timestamps inside [startedAt, now].
    if now_ms < started:
        reasons.append("Server time is before the quest start time.")
    if not in_window(fix["timestamp"]):
        reasons.append("Fresh GPS fix timestamp is outside the quest time window.")
    if steps_ev is not None and (not in_window(steps_ev["windowStart"]) or not in_window(steps_ev["windowEnd"])
                                 or steps_ev["windowEnd"] < steps_ev["windowStart"]):
        reasons.append("Step count window is outside the quest time window.")

    # 3. Freshness: the fix must be recent by server time.
    age_s = (now_ms - fix["timestamp"]) / 1000
    if age_s > cfg.MAX_FIX_AGE_S:
        reasons.append(f"GPS fix is stale ({age_s:.0f} s old, max {cfg.MAX_FIX_AGE_S:.0f} s). Get a new fix and retry.")

    # 4. Accuracy and mock location.
    if fix["accuracyM"] > cfg.MAX_ACCURACY_M:
        reasons.append(f"GPS fix too inaccurate ({fix['accuracyM']:.0f} m, max {cfg.MAX_ACCURACY_M:.0f} m). "
                       "Move outdoors / away from buildings and retry.")
    if fix.get("isMocked"):
        reasons.append("Mock location detected on the fresh fix. Disable mock-location apps.")
    if route.get("mockedCount", 0) > 0:
        reasons.append(f"Mock locations detected during the route ({route['mockedCount']} fixes).")

    # 5. Distance (run quests, CAFE-02).
    if req.get("distanceM"):
        dist = float(evidence.get("distanceM") or 0)
        target = req["distanceM"]
        if dist < target:
            reasons.append(f"Distance {dist:.0f} m is below the target of {target:.0f} m.")
            remaining.append({"requirement": "distance", "actual": round(dist), "target": target, "unit": "m"})
        elif route.get("fixCount", 0) < 2:
            reasons.append("Distance was reported without a GPS route (fewer than 2 valid fixes).")
        else:
            elapsed_s = max((now_ms - started) / 1000, 1)
            avg = dist / elapsed_s
            if avg > cfg.MAX_AVG_SPEED_MPS:
                reasons.append(f"Implausible average speed ({avg:.1f} m/s) for a walk/jog.")

    # 6. Steps (run quests, CAFE-02). Missing step data never counts as zero-but-OK.
    if req.get("steps"):
        target = req["steps"]
        if steps_ev is None:
            reasons.append("No step data was provided from Health Connect.")
            remaining.append({"requirement": "steps", "actual": 0, "target": target, "unit": "steps"})
        elif steps_ev["count"] < target:
            reasons.append(f"Steps {steps_ev['count']} are below the target of {target}.")
            remaining.append({"requirement": "steps", "actual": steps_ev["count"], "target": target, "unit": "steps"})

    # 7. Geofence (café quests): fresh fix inside café radius AND saved pin close to the fresh fix.
    cafe = req.get("cafe")
    if cafe:
        radius = cafe["radiusM"]
        fix_to_cafe = haversine_m(fix["lat"], fix["lng"], cafe["lat"], cafe["lng"])
        cafe_failed = False
        if fix_to_cafe > radius:
            reasons.append(f"You are {fix_to_cafe:.0f} m from the café (must be within {radius:.0f} m).")
            cafe_failed = True
        pin = progress.get("pin")
        if not pin:
            reasons.append("No confirmed pin. Confirm your location at the café first.")
            cafe_failed = True
        else:
            if pin.get("isMocked"):
                reasons.append("The saved pin came from a mock location.")
                cafe_failed = True
            if pin["accuracyM"] > cfg.MAX_ACCURACY_M:
                reasons.append(f"The saved pin was too inaccurate ({pin['accuracyM']:.0f} m). Confirm it again.")
                cafe_failed = True
            if not in_window(pin["timestamp"]):
                reasons.append("The saved pin is from before this quest started. Confirm it again.")
                cafe_failed = True
            pin_to_fix = haversine_m(pin["lat"], pin["lng"], fix["lat"], fix["lng"])
            if pin_to_fix > radius:
                reasons.append(f"Your pin is {pin_to_fix:.0f} m from your current position (max {radius:.0f} m).")
                cafe_failed = True
        if cafe_failed:
            remaining.append({"requirement": "cafe", "actual": round(fix_to_cafe), "target": radius,
                              "unit": "m from café"})

    return ValidationResult(passed=not reasons, reasons=reasons, remaining=remaining)
