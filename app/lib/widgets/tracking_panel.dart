import 'package:flutter/material.dart';

import '../gps_tracker.dart';

/// Grey box shown while GPS tracking is running for a quest.
class TrackingPanel extends StatelessWidget {
  final GpsTracker tracker;
  const TrackingPanel({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    final f = tracker.lastFix;
    final mocked = tracker.mockedCount > 0 ? ' · ${tracker.mockedCount} mocked' : '';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('● Tracking (keep the app open)', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Fixes: ${tracker.fixCount} accepted · ${tracker.rejectedCount} rejected$mocked'),
        if (f != null) Text('Last fix accuracy: ${f.accuracy.toStringAsFixed(0)} m'),
        if (tracker.message != null)
          Text(tracker.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    );
  }
}
