import 'package:flutter/material.dart';

/// One requirement line on a card:  [icon]  text
class RequirementRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const RequirementRow({super.key, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}
