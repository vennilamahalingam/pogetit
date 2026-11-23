/// Quest as returned by GET /quests: definition + this user's progress.
class Cafe {
  final double lat, lng, radiusM;
  Cafe(this.lat, this.lng, this.radiusM);
}

class Quest {
  final String id, title, type, description;
  final int xp;
  final double? targetDistanceM;
  final int? targetSteps;
  final Cafe? cafe;

  // Per-user progress
  final String status; // available | ongoing | completed
  final int progressPct;
  final double distanceM;
  final int steps;
  final int? startedAtMs;
  final Map<String, dynamic>? pin;
  final int fixCount, rejectedCount, mockedCount; // saved GPS route summary (restart recovery)

  Quest.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        type = j['type'],
        description = j['description'] ?? '',
        xp = (j['xp'] as num).toInt(),
        targetDistanceM = (j['requirements']?['distanceM'] as num?)?.toDouble(),
        targetSteps = (j['requirements']?['steps'] as num?)?.toInt(),
        cafe = j['requirements']?['cafe'] == null
            ? null
            : Cafe(
                (j['requirements']['cafe']['lat'] as num).toDouble(),
                (j['requirements']['cafe']['lng'] as num).toDouble(),
                (j['requirements']['cafe']['radiusM'] as num).toDouble(),
              ),
        status = j['status'] ?? 'available',
        progressPct = (j['progressPct'] as num?)?.toInt() ?? 0,
        distanceM = (j['distanceM'] as num?)?.toDouble() ?? 0,
        steps = (j['steps'] as num?)?.toInt() ?? 0,
        startedAtMs = (j['startedAtMs'] as num?)?.toInt(),
        pin = j['pin'],
        fixCount = (j['route']?['fixCount'] as num?)?.toInt() ?? 0,
        rejectedCount = (j['route']?['rejectedCount'] as num?)?.toInt() ?? 0,
        mockedCount = (j['route']?['mockedCount'] as num?)?.toInt() ?? 0;

  DateTime? get startedAt => startedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(startedAtMs!);

  /// Quests that need GPS distance tracking (RUN-01, RUN-02, CAFE-02).
  bool get needsTracking => targetDistanceM != null;

  /// Requirement summary for the card, built from metadata (never hardcoded).
  List<String> get requirementLines => [
        if (targetDistanceM != null) '${targetDistanceM!.toStringAsFixed(0)} m GPS distance',
        if (targetSteps != null) '≥ $targetSteps steps during the quest',
        if (cafe != null) 'Confirm location within ${cafe!.radiusM.toStringAsFixed(0)} m of the café',
      ];
}

/// Same formula as backend rules.progress_pct (display only; the server recomputes).
int progressPct(Quest q, {required double distanceM, required int steps, bool cafeOk = false}) {
  final ratios = <double>[
    if (q.targetDistanceM != null) (distanceM / q.targetDistanceM!).clamp(0, 1).toDouble(),
    if (q.targetSteps != null) (steps / q.targetSteps!).clamp(0, 1).toDouble(),
    if (q.cafe != null) cafeOk ? 1.0 : 0.0,
  ];
  if (ratios.isEmpty) return 0;
  return (ratios.reduce((a, b) => a + b) / ratios.length * 100).round();
}
