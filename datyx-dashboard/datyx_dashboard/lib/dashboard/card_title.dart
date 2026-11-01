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

/// [cards] with a 16 px gap between each and the next, as the tabs'
/// padding: the theme's cards have no margin of their own.
List<Widget> spaced(List<Widget> cards) => [
  for (final (i, card) in cards.indexed) ...[if (i > 0) const SizedBox(height: 16), card],
];
