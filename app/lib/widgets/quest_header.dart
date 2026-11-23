import 'package:flutter/material.dart';

import '../models.dart';

/// Colour per quest type: run = teal, café = coffee brown.
Color questAccent(Quest q) => q.type == 'run' ? const Color(0xFF2E7D6B) : const Color(0xFF9A5B2E);

/// Top row of a quest card: [icon]  Title / ID  [+XP badge]
class QuestHeader extends StatelessWidget {
  final Quest quest;
  const QuestHeader({super.key, required this.quest});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = questAccent(quest);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: accent.withValues(alpha: 0.12),
        child: Icon(quest.type == 'run' ? Icons.directions_run : Icons.local_cafe, color: accent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(quest.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(quest.id,
              style: text.labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.8)),
        ]),
      ),
      _XpBadge(xp: quest.xp),
    ]);
  }
}

class _XpBadge extends StatelessWidget {
  final int xp;
  const _XpBadge({required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(20)),
      child: Text('+$xp XP',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF8A6100))),
    );
  }
}
