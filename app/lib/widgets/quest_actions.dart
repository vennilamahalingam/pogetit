import 'package:flutter/material.dart';

import '../models.dart';

/// The buttons at the bottom of a card. Which ones appear depends on the quest status.
/// Every button only calls a callback; the logic lives in home_screen.dart.
class QuestActions extends StatelessWidget {
  final Quest quest;
  final bool tracking; // GPS is running for this quest
  final bool busy; // a request is in flight -> buttons disabled (double-tap guard)
  final bool canInstallHealthConnect;
  final VoidCallback onAccept, onStartTracking, onStopTracking, onRefreshSteps;
  final VoidCallback onInstallHealthConnect, onOpenPin, onValidate;

  const QuestActions({
    super.key,
    required this.quest,
    required this.tracking,
    required this.busy,
    required this.canInstallHealthConnect,
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
    final List<Widget> buttons = switch (q.status) {
      'available' => [
          FilledButton(onPressed: busy ? null : onAccept, child: const Text('Accept / Start')),
        ],
      'ongoing' => [
          if (q.needsTracking && tracking)
            OutlinedButton(onPressed: onStopTracking, child: const Text('Stop tracking')),
          if (q.needsTracking && !tracking)
            OutlinedButton(
              onPressed: busy ? null : onStartTracking,
              child: Text(q.distanceM > 0 ? 'Resume tracking' : 'Start tracking'),
            ),
          if (q.targetSteps != null)
            TextButton(onPressed: busy ? null : onRefreshSteps, child: const Text('Refresh steps')),
          if (canInstallHealthConnect)
            TextButton(onPressed: onInstallHealthConnect, child: const Text('Get Health Connect')),
          if (q.cafe != null)
            OutlinedButton.icon(
              onPressed: busy ? null : onOpenPin,
              icon: const Icon(Icons.push_pin),
              label: Text(q.pin == null ? 'Confirm location' : 'Re-confirm location'),
            ),
          FilledButton(onPressed: busy ? null : onValidate, child: Text(busy ? 'Validating…' : 'Validate')),
        ],
      _ => [const Chip(label: Text('Completed ✓'))],
    };
    return Wrap(spacing: 8, runSpacing: 4, children: buttons);
  }
}
