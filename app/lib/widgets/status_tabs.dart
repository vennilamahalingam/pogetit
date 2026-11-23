import 'package:flutter/material.dart';

/// Single-line tabs: Available n · Ongoing n · Completed n
class StatusTabs extends StatelessWidget {
  final String selected;
  final Map<String, int> counts; // status -> number of quests
  final ValueChanged<String> onChanged;
  const StatusTabs({super.key, required this.selected, required this.counts, required this.onChanged});

  static const statuses = ['available', 'ongoing', 'completed'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        segments: [
          for (final s in statuses)
            ButtonSegment(
              value: s,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${s[0].toUpperCase()}${s.substring(1)} ${counts[s] ?? 0}'),
              ),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (sel) => onChanged(sel.first),
      ),
    );
  }
}
