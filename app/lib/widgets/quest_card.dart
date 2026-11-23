import 'package:flutter/material.dart';

import '../gps_tracker.dart';
import '../models.dart';
import 'quest_actions.dart';
import 'quest_header.dart';
import 'requirement_row.dart';
import 'tracking_panel.dart';

/// One quest card. It only DISPLAYS data and forwards button taps;
/// all state and server calls stay in home_screen.dart.
///
///   QuestHeader        icon · title · ID · +XP
///   description
///   RequirementRow ×N  distance / steps / café   (built from quest data)
///   progress bar + %
///   live details       distance, steps, pin status
///   TrackingPanel      only while GPS is running
///   QuestActions       buttons for the current status
class QuestCard extends StatelessWidget {
  final Quest quest;
  final GpsTracker? tracker; // non-null only while tracking THIS quest
  final int? liveSteps; // latest Health Connect reading (null = none)
  final String? stepsProblem; // why steps couldn't be read
  final bool canInstallHealthConnect;
  final bool busy;
  final VoidCallback onAccept, onStartTracking, onStopTracking, onRefreshSteps;
  final VoidCallback onInstallHealthConnect, onOpenPin, onValidate;

  const QuestCard({
    super.key,
    required this.quest,
    required this.tracker,
    required this.liveSteps,
    required this.stepsProblem,
    required this.canInstallHealthConnect,
    required this.busy,
    required this.onAccept,
    required this.onStartTracking,
    required this.onStopTracking,
    required this.onRefreshSteps,
    required this.onInstallHealthConnect,
    required this.onOpenPin,
    required this.onValidate,
  });

  @override
  Widget build(BuildContext context) {
    final q = quest;
    final ongoing = q.status == 'ongoing';
    final accent = questAccent(q);
    final scheme = Theme.of(context).colorScheme;
    final err = scheme.error;

    // Live values (display only — the server recalculates everything on validate).
    final distance = tracker?.distanceM ?? q.distanceM;
    final steps = liveSteps ?? q.steps;
    final cafeOk = q.cafe != null &&
        q.pin != null &&
        haversineM(q.pin!['lat'], q.pin!['lng'], q.cafe!.lat, q.cafe!.lng) <= q.cafe!.radiusM;
    final pct = ongoing ? progressPct(q, distanceM: distance, steps: steps, cafeOk: cafeOk) : q.progressPct;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QuestHeader(quest: q),

          if (q.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(q.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 4),

          // Requirements — one row per target in the quest's data.
          if (q.targetDistanceM != null)
            RequirementRow(
                icon: Icons.straighten, color: accent, label: '${q.targetDistanceM!.toStringAsFixed(0)} m GPS distance'),
          if (q.targetSteps != null)
            RequirementRow(icon: Icons.directions_walk, color: accent, label: '${q.targetSteps} steps during the quest'),
          if (q.cafe != null)
            RequirementRow(
                icon: Icons.place,
                color: accent,
                label: 'Check in within ${q.cafe!.radiusM.toStringAsFixed(0)} m of the café'),
          const SizedBox(height: 12),

          _ProgressRow(pct: pct, color: accent),

          // Live details while the quest is running.
          if (q.status != 'available' && q.needsTracking)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Distance: ${distance.toStringAsFixed(0)} / ${q.targetDistanceM!.toStringAsFixed(0)} m'),
            ),
          if (ongoing && q.targetSteps != null) ...[
            Text('Steps (Health Connect): ${liveSteps ?? '—'} / ${q.targetSteps}'),
            if (liveSteps == 0)
              Text('No steps recorded yet. Make sure Samsung Health syncs to Health Connect.',
                  style: TextStyle(color: err, fontSize: 12)),
            if (stepsProblem != null) Text(stepsProblem!, style: TextStyle(color: err, fontSize: 12)),
          ],
          if (ongoing && q.cafe != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(q.pin == null
                  ? 'Café pin: not confirmed'
                  : 'Café pin: saved (±${(q.pin!['accuracyM'] as num).toStringAsFixed(0)} m, '
                      '${cafeOk ? 'inside' : 'outside'} café area)'),
            ),
          if (tracker != null) TrackingPanel(tracker: tracker!),
          if (ongoing && pct >= 100)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Targets reached. Tap Validate: it stays Ongoing until the server confirms.'),
            ),
          const SizedBox(height: 8),

          QuestActions(
            quest: q,
            tracking: tracker != null,
            busy: busy,
            canInstallHealthConnect: canInstallHealthConnect,
            onAccept: onAccept,
            onStartTracking: onStartTracking,
            onStopTracking: onStopTracking,
            onRefreshSteps: onRefreshSteps,
            onInstallHealthConnect: onInstallHealthConnect,
            onOpenPin: onOpenPin,
            onValidate: onValidate,
          ),
        ]),
      ),
    );
  }
}

/// Coloured progress bar with the % on the right.
class _ProgressRow extends StatelessWidget {
  final int pct;
  final Color color;
  const _ProgressRow({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('$pct%', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}
