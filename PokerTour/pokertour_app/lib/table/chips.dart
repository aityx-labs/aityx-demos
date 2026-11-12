import 'package:flutter/material.dart';

/// Chip denominations and their colors, as casinos use them: the biggest
/// first.
const chipDenominations = <(int, Color, Color)>[
  (1000, Color(0xFFE8B04B), Color(0xFF8A6220)),
  (500, Color(0xFF8E54D9), Color(0xFF4B2A7A)),
  (100, Color(0xFF2B2B33), Color(0xFF0E0E12)),
  (25, Color(0xFF3EA86B), Color(0xFF1E5C3A)),
  (5, Color(0xFFD63B3B), Color(0xFF7A1F1F)),
  (1, Color(0xFFE8E6E1), Color(0xFF8C8A85)),
];

/// A pile of chips worth [amount], drawn as stacked columns, one per
/// denomination, the biggest on the left; with the amount beside it when
/// [label] is set. Big amounts are shown with up to [maxChips] chips, the
/// smaller denominations dropped first.
class ChipPile extends StatelessWidget {
  const ChipPile(
    this.amount, {
    super.key,
    this.label = true,
    this.chipWidth = 18,
    this.maxChips = 24,
  });

  final int amount;
  final bool label;
  final double chipWidth;
  final int maxChips;

  /// The columns: each a denomination's color pair and how many chips.
  static List<((int, Color, Color), int)> columns(int amount, int maxChips) {
    var left = amount;
    final out = <((int, Color, Color), int)>[];
    for (final d in chipDenominations) {
      final n = left ~/ d.$1;
      if (n > 0) {
        out.add((d, n));
        left -= n * d.$1;
      }
    }
    // Too many chips: show fewer of each, the small ones first, keeping
    // at least one of every denomination present.
    var total = out.fold(0, (s, c) => s + c.$2);
    for (var i = out.length - 1; i >= 0 && total > maxChips; i--) {
      final (d, n) = out[i];
      final keep = n.clamp(1, 10);
      total -= n - keep;
      out[i] = (d, keep);
    }
    for (var i = out.length - 1; i >= 0 && total > maxChips; i--) {
      final (d, n) = out[i];
      total -= n - 1;
      out[i] = (d, 1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    final cols = columns(amount, maxChips);
    final tallest = cols.fold(0, (m, c) => c.$2 > m ? c.$2 : m);
    final chipHeight = chipWidth * 0.42;
    final step = chipHeight * 0.55;
    final height = chipHeight + (tallest - 1) * step;
    final width = cols.length * chipWidth + (cols.length - 1) * 2;
    final pile = CustomPaint(
      size: Size(width, height),
      painter: _PilePainter(cols, chipWidth, chipHeight, step),
    );
    if (!label) return pile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pile,
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$amount',
            style: const TextStyle(
              color: Color(0xFFE8B04B),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _PilePainter extends CustomPainter {
  const _PilePainter(this.columns, this.w, this.h, this.step);

  final List<((int, Color, Color), int)> columns;
  final double w;
  final double h;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    var x = 0.0;
    for (final ((_, face, edge), n) in columns) {
      for (var i = 0; i < n; i++) {
        final cy = size.height - h / 2 - i * step;
        final rect = Rect.fromCenter(
          center: Offset(x + w / 2, cy),
          width: w,
          height: h,
        );
        // The edge below the face, then the face, then the marks.
        canvas.drawOval(
          rect.shift(const Offset(0, 1.2)),
          Paint()..color = edge,
        );
        canvas.drawOval(rect, Paint()..color = face);
        final marks = Paint()
          ..color = Colors.white.withValues(
            alpha: face == const Color(0xFFE8E6E1) ? 0.0 : 0.85,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        for (var k = 0; k < 4; k++) {
          final a = k * 3.1416 / 2 + 0.4;
          canvas.drawArc(rect.deflate(0.8), a, 0.45, false, marks);
        }
        if (face == const Color(0xFFE8E6E1)) {
          canvas.drawOval(
            rect.deflate(0.5),
            Paint()
              ..color = const Color(0xFF8C8A85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        }
      }
      x += w + 2;
    }
  }

  @override
  bool shouldRepaint(_PilePainter old) =>
      old.columns != columns || old.w != w || old.h != h;
}
