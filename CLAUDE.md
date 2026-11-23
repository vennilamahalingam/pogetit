# PoGetIt — GPS Quest Validation & Step Counting Prototype

## What this is
A functional Android prototype (an evaluation build for a client) in which a user browses quests, accepts/starts them, tracks progress with real GPS and Health Connect steps, pins and confirms a location, validates completion on the backend and receives XP.

**Priority: working device sensors and verifiable, server-side quest completion. Visual polish is not a priority.**
Client guidance: deliver the core flow first. The most important part is how a quest loads for a user and how the user completes it, **especially quest validation**.

Evaluation weights: GPS reliability & pin verification 30% · Health Connect/steps 25% · backend validation & XP integrity 20% · quest state/progress UX 15% · code quality, tests & handover 10%.

## Tech stack (fixed by client — do not change without asking me)
- **App:** Flutter/Dart (Android only). Kotlin platform channel only if a Flutter plugin can't do it.
- **Backend:** Python + FastAPI, Firebase Admin SDK for all trusted Firestore writes.
- **Data/Auth:** Firebase Firestore + Firebase Anonymous Authentication.
- **Location:** `geolocator` (fused location provider). No Google Maps view. Pin confirmation = coordinate-based confirm control with a clear location preview (or a lightweight map picker only if needed).
- **Steps:** Android Health Connect via the `health` Flutter package. Native step sensor is allowed only as a *documented* fallback.
- **Tests:** pytest for backend rules; real Android device for GPS, permissions and Health Connect.

## Repo layout
```
/app        Flutter app
/backend    FastAPI service (app/, tests/, seed script)
README.md
CLAUDE.md
```

## Data model (Firestore)
- `quests/{questId}`: id, title, type (`run` | `cafe`), description, requirements { distanceM?, steps?, cafe? { lat, lng, radiusM } }, xp, active. **All targets and XP are configurable metadata, never hardcoded in app logic.**
- `users/{uid}`: xp (int), createdAt.
- `users/{uid}/questProgress/{questId}`: status (`available` | `ongoing` | `completed`), acceptedAt, startedAt, distanceM, steps, progressPct, lastSnapshotAt, pin? { lat, lng, accuracyM, timestamp }.
- `validations/{autoId}`: uid, questId, submitted evidence, result (pass/fail), reasons[], createdAt.
- Clients may read quests and their own progress. **XP, `completed` status and validation records are written only by the backend.**

### Seeded quests (seed script in /backend)
| ID | Title | Requirements | XP |
|---|---|---|---|
| RUN-01 | Beginner Jog | 1,000 m GPS distance AND ≥1,200 steps during the active quest | 100 |
| RUN-02 | Step-Up Run | 2,000 m AND ≥2,500 steps | 150 |
| CAFE-01 | Local Café Stop | Fresh GPS fix + confirmed pin within 50 m of seeded café | 80 |
| CAFE-02 | Walk for Your Coffee | ≥500 m walk + steps, then pin within 50 m of seeded café | 120 |

Seed two realistic test café coordinates, and provide an easy way (seed script argument or admin endpoint) to substitute reviewer-chosen coordinates.
**Out of scope for now:** user photo for café quests — do not build any photo capture/upload.

## Quest states and progress
- Available → Ongoing (on Accept/Start) → Completed (**only** after backend validation succeeds).
- Progress % = average of each requirement's capped ratio (min(actual/target, 1)) × 100, rounded to an integer. Example: 500/1,000 m and 600/1,200 steps = 50%.
- Café arrival/check-in is binary: 0% or 100%.
- A quest can show 100% but stays Ongoing until validation succeeds; success sets it to Completed at 100%.
- **Out of scope for now:** the 85–90% fallback "Finish" button. Do not build it (it may be added later once the client clarifies the rule).
- Refresh progress while active and persist a recoverable snapshot so progress survives app restart.
- **Never award XP on accept, start, pin placement or a client-side progress value.**

## GPS tracking rules (app side)
- Foreground tracking only, during active run/walk quests.
- Distance = sum of haversine distances between valid successive fixes.
- Reject samples with poor accuracy (e.g. > 30 m) and implausible jumps (implied speed > ~8 m/s for walking/jogging).
- Detect mock locations (`position.isMocked`) and flag them.
- Handle GPS disabled, permission denied and indoor/poor-signal cases with clear messages.

## Pin confirmation
- Get a fresh GPS fix + accuracy, show a preview, user confirms the pin.
- Save coordinates, timestamp, accuracy, questId and uid.
- **A pin alone is not proof of presence.** Backend must compare the pin with a fresh device GPS fix and the café geofence.

## Steps (Health Connect)
- Request explicit permission. Read steps for the quest's start → now/end window.
- Use aggregated step totals (not summed raw records) to avoid double-counting overlapping sources.
- Clearly handle: Health Connect not installed/unavailable, permission denied, zero data.
- **Never fabricate or silently substitute steps.**

## Backend API (FastAPI)
Every request carries the Firebase ID token (`Authorization: Bearer <token>`); verify it with Firebase Admin and use its uid.
- `GET /quests` — quest definitions + the user's status/progress for each.
- `POST /quests/{id}/accept` — Available → Ongoing, sets startedAt.
- `POST /quests/{id}/progress` — saves a progress snapshot (distance, steps, pct). Informational only; never completes a quest.
- `POST /quests/{id}/pin` — saves a confirmed pin.
- `POST /quests/{id}/validate` — evidence: distanceM, route summary (fix count, rejected count), steps + window, pin, fresh fix { lat, lng, accuracyM, timestamp, isMocked }.

### Validation rules (`/validate`) — the most important code in the project
Check in this order and return **all** failing reasons with readable messages:
1. Quest exists and is active; user's status is `ongoing` (if already `completed` → return "already completed", no XP).
2. Time window: now is after startedAt; evidence timestamps fall inside the quest window.
3. Freshness: fresh fix timestamp within ~2 minutes of server time.
4. Accuracy: fresh fix accuracy ≤ 30 m (configurable); reject `isMocked`.
5. Distance ≥ target (run quests, CAFE-02).
6. Steps ≥ target (run quests, CAFE-02).
7. Geofence (café quests): haversine(fresh fix, café) ≤ radiusM AND haversine(pin, fresh fix) is small (e.g. ≤ radiusM).
8. On pass: in **one Firestore transaction**, re-check the status is still `ongoing`, set `completed` + 100%, increment user XP and write the validation record. This guarantees XP is granted exactly once, even with double taps or retries.
9. On fail: write a failed validation record, keep the quest `ongoing`, return the remaining requirements.

Put the rule logic in pure functions (no Firestore) so it is easy to unit test.

## Error handling (app must show actionable messages)
Denied permissions, Health Connect unavailable, zero step data, GPS disabled, stale/inaccurate fix, backend unreachable, duplicate validation, app restart mid-quest.

## Tests (pytest)
Must cover: pass and fail for each quest type; out-of-radius check-in; insufficient steps; insufficient distance; stale fix; poor accuracy; mocked location; duplicate validation grants XP once; progress % calculation (including the 50% example).

## Deliverables (from client spec)
Installable APK; README (setup, Firebase config, API instructions, permissions, test-device requirements, limitations, known issues); screen recording of the full flow; examples of pass and fail shown in the app.
Note: the spec asks for source code on GitHub — **keep the repo private and do not share source until terms are agreed.**

## Build order (do one step at a time, stop after each for me to test)
1. Backend skeleton: FastAPI, Firebase Admin, token auth, seed script, `GET /quests`.
2. Validation rules as pure functions + pytest suite (all green).
3. `/accept`, `/progress`, `/pin`, `/validate` with the transaction.
4. Flutter: anonymous auth, homepage with Available/Ongoing/Completed chips, quest cards (title, requirements, % + progress bar, XP, buttons).
5. Accept/Start → GPS tracking with filtering → live distance progress.
6. Health Connect steps for the quest window → combined progress.
7. Pin confirmation + café validation.
8. Validate button → show pass/fail feedback and remaining requirements; XP display.
9. Error handling pass, restart recovery.
10. README, APK build, demo-expiry/kill-switch for the shared APK.

## How to work with me
- I must understand and be able to change this code myself. **After each step, explain what you built and why, in simple terms**, especially the validation logic.
- Plan before coding; keep changes small; don't add features outside this spec.
- Ask me before changing the stack, adding dependencies beyond the obvious ones, or deciding open questions.
- Never commit secrets (service account JSON, `google-services.json` keys) — use `.env` / gitignore.
