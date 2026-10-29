import 'package:flutter/material.dart';

import '../engine/game.dart';
import '../theme.dart';

/// A face for each strategy, and one for strategies written in the app.
String avatarFor(String strategyId) => switch (strategyId) {
  'rock' => '🪨',
  'maniac' => '🤪',
  'station' => '📞',
  'mathematician' => '🧮',
  'shark' => '🦈',
  _ => '🎭',
};

/// The ring colors, one per seat, cycling.
const _rings = [
  Color(0xFF4CC38A),
  Color(0xFF58A6FF),
  Color(0xFFE8B04B),
  Color(0xFFD17BE8),
  Color(0xFFF08A5D),
  Color(0xFF5FD3D3),
  Color(0xFFF0506E),
  Color(0xFFA3D977),
  Color(0xFFC9A77C),
];

Color ringFor(Seat seat) => _rings[(seat.id - 1) % _rings.length];

/// A player's avatar: their strategy's face in a ring of their color,
/// lit orange while they decide, amber when they win, gray when out.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.seat,
    this.size = 44,
    this.acting = false,
    this.winner = false,
    this.dim = false,
  });

  final Seat seat;
  final double size;
  final bool acting;
  final bool winner;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final ring = acting
        ? Aityx.orange
        : winner
        ? Aityx.amber
        : dim
        ? Aityx.dim
        : ringFor(seat);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dim ? Aityx.bg1 : Aityx.bg2,
        border: Border.all(color: ring, width: acting || winner ? 3 : 2),
        boxShadow: acting
            ? [
                BoxShadow(
                  color: Aityx.orange.withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
              ]
            : winner
            ? [
                BoxShadow(
                  color: Aityx.amber.withValues(alpha: 0.5),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Opacity(
        opacity: dim ? 0.4 : 1,
        child: Text(
          avatarFor(seat.strategyId),
          style: TextStyle(fontSize: size * 0.5, height: 1),
        ),
      ),
    );
  }
}
