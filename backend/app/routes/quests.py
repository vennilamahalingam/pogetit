"""Quest endpoints. The decisions live in app/rules.py; this file only reads/writes Firestore."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

from app import rules
from app.auth import get_current_uid
from app.firebase import get_db
from app.models import Fix, ProgressRequest, ValidateRequest

router = APIRouter()


# ---------- helpers ----------
def now_ms() -> int:
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def to_ms(value) -> int | None:
    """Firestore timestamp -> epoch ms (None stays None)."""
    return int(value.timestamp() * 1000) if value is not None else None


def progress_ref(db, uid: str, quest_id: str):
    return db.collection("users").document(uid).collection("questProgress").document(quest_id)


def load_quest(db, quest_id: str) -> dict:
    snap = db.collection("quests").document(quest_id).get()
    if not snap.exists:
        raise HTTPException(404, "Quest not found.")
    return snap.to_dict()


def load_progress(db, uid: str, quest_id: str) -> dict | None:
    snap = progress_ref(db, uid, quest_id).get()
    if not snap.exists:
        return None
    p = snap.to_dict()
    p["startedAtMs"] = to_ms(p.get("startedAt"))
    return p


def progress_view(p: dict | None) -> dict:
    """The per-user part of a quest card, safe to send to the app."""
    p = p or {}
    return {
        "status": p.get("status", "available"),
        "progressPct": p.get("progressPct", 0),
        "distanceM": p.get("distanceM", 0),
        "steps": p.get("steps", 0),
        "startedAtMs": to_ms(p.get("startedAt")),
        "lastSnapshotAtMs": to_ms(p.get("lastSnapshotAt")),
        "pin": p.get("pin"),
        "route": p.get("route"),
    }


def require_ongoing(p: dict | None) -> None:
    status = (p or {}).get("status", "available")
    if status != "ongoing":
        raise HTTPException(409, f"Quest is '{status}', not ongoing.")


# ---------- endpoints ----------
@router.get("/quests")
def list_quests(uid: str = Depends(get_current_uid)):
    db = get_db()
    user_ref = db.collection("users").document(uid)
    user = user_ref.get()
    if not user.exists:
        user_ref.set({"xp": 0, "createdAt": firestore.SERVER_TIMESTAMP})
        xp = 0
    else:
        xp = user.to_dict().get("xp", 0)

    progress = {s.id: s.to_dict() for s in user_ref.collection("questProgress").stream()}
    quests = []
    for snap in db.collection("quests").where(filter=firestore.FieldFilter("active", "==", True)).stream():
        q = snap.to_dict()
        quests.append({**q, **progress_view(progress.get(snap.id))})
    quests.sort(key=lambda q: q["id"])
    return {"uid": uid, "xp": xp, "quests": quests}


@router.post("/quests/{quest_id}/accept")
def accept_quest(quest_id: str, uid: str = Depends(get_current_uid)):
    """Available -> Ongoing. startedAt is server time. Never awards XP."""
    db = get_db()
    quest = load_quest(db, quest_id)
    if not quest.get("active"):
        raise HTTPException(409, "This quest is not active.")
    p = load_progress(db, uid, quest_id)
    status = (p or {}).get("status", "available")
    if status == "completed":
        raise HTTPException(409, "Quest already completed.")
    if status == "ongoing":  # idempotent: accepting twice keeps the original start time
        return progress_view(p)
    now = datetime.now(timezone.utc)
    data = {"status": "ongoing", "acceptedAt": now, "startedAt": now,
            "distanceM": 0, "steps": 0, "progressPct": 0, "lastSnapshotAt": now,
            "route": {"fixCount": 0, "rejectedCount": 0, "mockedCount": 0}}
    progress_ref(db, uid, quest_id).set(data)
    return progress_view(data)


@router.post("/quests/{quest_id}/progress")
def save_progress(quest_id: str, body: ProgressRequest, uid: str = Depends(get_current_uid)):
    """Recoverable snapshot. Informational only: never completes a quest or awards XP."""
    db = get_db()
    quest = load_quest(db, quest_id)
    p = load_progress(db, uid, quest_id)
    require_ongoing(p)
    req = quest["requirements"]
    steps = body.steps if body.steps is not None else p.get("steps", 0)
    pct = rules.progress_pct(req, body.distanceM, steps, rules.pin_inside_cafe(req, p.get("pin")))
    update = {"distanceM": body.distanceM, "steps": steps, "progressPct": pct,
              "lastSnapshotAt": datetime.now(timezone.utc)}
    if body.route is not None:
        update["route"] = body.route.model_dump()
    progress_ref(db, uid, quest_id).update(update)
    return progress_view({**p, **update})


@router.post("/quests/{quest_id}/pin")
def save_pin(quest_id: str, body: Fix, uid: str = Depends(get_current_uid)):
    """Saves the confirmed pin. A pin alone proves nothing; /validate checks it against a fresh fix."""
    db = get_db()
    quest = load_quest(db, quest_id)
    if not quest["requirements"].get("cafe"):
        raise HTTPException(400, "This quest has no café check-in.")
    p = load_progress(db, uid, quest_id)
    require_ongoing(p)
    pin = {**body.model_dump(), "questId": quest_id, "uid": uid, "savedAtMs": now_ms()}
    req = quest["requirements"]
    pct = rules.progress_pct(req, p.get("distanceM", 0), p.get("steps", 0), rules.pin_inside_cafe(req, pin))
    progress_ref(db, uid, quest_id).update({"pin": pin, "progressPct": pct})
    return progress_view({**p, "pin": pin, "progressPct": pct})


@firestore.transactional
def _complete_once(transaction, prog_ref, user_ref, val_ref, xp: int, record: dict) -> bool:
    """Inside ONE transaction: re-read status; only if still 'ongoing' -> completed + XP + record.

    If two validate calls race (double tap / retry), Firestore re-runs the loser's
    transaction, it sees 'completed' and returns False, so XP is added exactly once.
    """
    snap = prog_ref.get(transaction=transaction)
    if not snap.exists or snap.to_dict().get("status") != "ongoing":
        return False
    now = datetime.now(timezone.utc)
    transaction.update(prog_ref, {"status": "completed", "progressPct": 100, "completedAt": now})
    transaction.set(user_ref, {"xp": firestore.Increment(xp)}, merge=True)
    transaction.set(val_ref, {**record, "xpAwarded": xp, "createdAt": now})
    return True


@router.post("/quests/{quest_id}/validate")
def validate(quest_id: str, body: ValidateRequest, uid: str = Depends(get_current_uid)):
    db = get_db()
    snap = db.collection("quests").document(quest_id).get()
    quest = snap.to_dict() if snap.exists else None
    p = load_progress(db, uid, quest_id)
    evidence = body.model_dump()
    result = rules.validate_quest(quest, p, evidence, now_ms())

    user_ref = db.collection("users").document(uid)
    val_ref = db.collection("validations").document()
    record = {"uid": uid, "questId": quest_id, "evidence": evidence,
              "storedPin": (p or {}).get("pin"), "reasons": result.reasons}

    xp_awarded = 0
    if result.passed:
        granted = _complete_once(db.transaction(), progress_ref(db, uid, quest_id), user_ref, val_ref,
                                 quest["xp"], {**record, "result": "pass"})
        if granted:
            xp_awarded = quest["xp"]
        else:
            result = rules.ValidationResult(False, ["Quest already completed. XP was already awarded."],
                                            already_completed=True)
    else:
        val_ref.set({**record, "result": "fail", "xpAwarded": 0, "createdAt": firestore.SERVER_TIMESTAMP})

    user = user_ref.get()
    final = load_progress(db, uid, quest_id)
    return {
        "passed": result.passed,
        "alreadyCompleted": result.already_completed,
        "reasons": result.reasons,
        "remaining": result.remaining,
        "xpAwarded": xp_awarded,
        "totalXp": (user.to_dict() or {}).get("xp", 0) if user.exists else 0,
        **progress_view(final),
    }
