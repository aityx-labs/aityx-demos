import 'package:flutter/material.dart' hide Card;

import '../engine/cards.dart';

/// A playing card, face up: the rank and the suit, red or black on white.
class CardWidget extends StatelessWidget {
  const CardWidget(this.card, {super.key, this.height = 56, this.dim = false});

  final Card card;
  final double height;

  /// Faded: a folded hand.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final width = height * 0.72;
    final color = card.suit.red
        ? const Color(0xFFD63B3B)
        : const Color(0xFF1B1B22);
    return Opacity(
      opacity: dim ? 0.35 : 1,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F2),
          borderRadius: BorderRadius.circular(height * 0.1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              card.rankLabel,
              style: TextStyle(
                color: color,
                fontSize: height * 0.4,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            Text(
              card.suit.symbol,
              style: TextStyle(
                color: color,
                fontSize: height * 0.34,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card's back, or the place one would be.
class CardSlot extends StatelessWidget {
  const CardSlot({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: height * 0.72,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height * 0.1),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
      ),
    );
  }
}
