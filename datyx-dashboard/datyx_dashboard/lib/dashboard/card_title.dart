import 'package:flutter/material.dart';

import '../theme.dart';

/// A card's title, with the endpoint it shows beside it.
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          subtitle,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    ],
  );
}
