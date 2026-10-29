import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'board.dart';

/// Where the view looks on the infinite board: the cell at its center and
/// how many pixels a cell is. Dragging moves it, the wheel and pinching
/// zoom it around the pointer.
class BoardCamera extends ChangeNotifier {
  BoardCamera({this.centerX = 0, this.centerY = 0, this.scale = 14});

  static const minScale = 2.0;
  static const maxScale = 64.0;

  double centerX;
  double centerY;

  /// Pixels per cell.
  double scale;

  /// The view's size, set by the view as it lays out.
  Size viewport = Size.zero;

  /// Moves the view by [delta] pixels, the way the board was dragged.
  void moveBy(Offset delta) {
    centerX -= delta.dx / scale;
    centerY -= delta.dy / scale;
    notifyListeners();
  }

  /// Zooms by [factor], keeping the cell under [focal] (in view pixels)
  /// where it is.
  void zoomAt(Offset focal, double factor) {
    final next = (scale * factor).clamp(minScale, maxScale);
    if (next == scale) return;
    final before = toBoard(focal);
    scale = next;
    final after = toBoard(focal);
    centerX += before.dx - after.dx;
    centerY += before.dy - after.dy;
    notifyListeners();
  }

  /// Back to the origin at the default zoom.
  void reset() {
    centerX = 0;
    centerY = 0;
    scale = 14;
    notifyListeners();
  }

  /// The board coordinates (fractional cells) under a view pixel.
  Offset toBoard(Offset pixel) => Offset(
    centerX + (pixel.dx - viewport.width / 2) / scale,
    centerY + (pixel.dy - viewport.height / 2) / scale,
  );

  /// The cell under a view pixel.
  Cell cellAt(Offset pixel) {
    final at = toBoard(pixel);
    return (x: at.dx.floor(), y: at.dy.floor());
  }

  /// The view pixel of a board coordinate.
  Offset toView(double x, double y) => Offset(
    (x - centerX) * scale + viewport.width / 2,
    (y - centerY) * scale + viewport.height / 2,
  );

  /// The cells the view shows, inclusive.
  ({int left, int top, int right, int bottom}) get visible => (
    left: (centerX - viewport.width / 2 / scale).floor(),
    top: (centerY - viewport.height / 2 / scale).floor(),
    right: (centerX + viewport.width / 2 / scale).ceil(),
    bottom: (centerY + viewport.height / 2 / scale).ceil(),
  );
}

/// A cluster aityx recognized, labeled on the board with its pattern.
class BoardLabel {
  const BoardLabel(this.cluster, this.name);

  final Cluster cluster;
  final String name;
}

/// The board on an infinite grid: live cells in orange, those born in this
/// generation in green, recognized patterns outlined and named. Drag to
/// move, scroll or pinch to zoom, tap a cell to flip it.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.board,
    required this.camera,
    this.labels = const [],
    this.onToggle,
    this.hint,
  });

  final Board board;
  final BoardCamera camera;
  final List<BoardLabel> labels;
  final ValueChanged<Cell>? onToggle;

  /// Shown over an empty board.
  final String? hint;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  double _scaleAtStart = 1;
  Offset _lastFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.camera.viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              widget.camera.zoomAt(
                event.localPosition,
                math.exp(-event.scrollDelta.dy / 300),
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _scaleAtStart = widget.camera.scale;
              _lastFocal = details.localFocalPoint;
            },
            onScaleUpdate: (details) {
              final camera = widget.camera;
              if (details.scale != 1) {
                camera.zoomAt(
                  details.localFocalPoint,
                  _scaleAtStart * details.scale / camera.scale,
                );
              }
              camera.moveBy(details.localFocalPoint - _lastFocal);
              _lastFocal = details.localFocalPoint;
            },
            onTapUp: widget.onToggle == null
                ? null
                : (details) =>
                      widget.onToggle!(widget.camera.cellAt(details.localPosition)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _BoardPainter(
                      board: widget.board,
                      labels: widget.labels,
                      camera: widget.camera,
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ),
                ),
                if (widget.hint != null && widget.board.alive.isEmpty)
                  Center(
                    child: IgnorePointer(
                      child: Text(
                        widget.hint!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.labels,
    required this.camera,
    required this.textScaler,
  }) : super(repaint: camera);

  final Board board;
  final List<BoardLabel> labels;
  final BoardCamera camera;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Aityx.bg0);
    final s = camera.scale;
    final visible = camera.visible;

    // The grid, once cells are big enough to tell apart; the axes always,
    // so the origin can be found again.
    final grid = Paint()
      ..color = Aityx.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = Aityx.dim
      ..strokeWidth = 1;
    if (s >= 7) {
      for (var x = visible.left; x <= visible.right; x++) {
        final px = camera.toView(x.toDouble(), 0).dx;
        canvas.drawLine(Offset(px, 0), Offset(px, size.height), x == 0 ? axis : grid);
      }
      for (var y = visible.top; y <= visible.bottom; y++) {
        final py = camera.toView(0, y.toDouble()).dy;
        canvas.drawLine(Offset(0, py), Offset(size.width, py), y == 0 ? axis : grid);
      }
    } else {
      final origin = camera.toView(0, 0);
      canvas.drawLine(Offset(origin.dx, 0), Offset(origin.dx, size.height), axis);
      canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), axis);
    }

    // The cells, with a hairline gap between them once there's room.
    final alive = Paint()..color = Aityx.orange;
    final born = Paint()..color = Aityx.green;
    final gap = s >= 6 ? 1.0 : 0.0;
    for (final cell in board.alive) {
      if (cell.x < visible.left ||
          cell.x > visible.right ||
          cell.y < visible.top ||
          cell.y > visible.bottom) {
        continue;
      }
      final at = camera.toView(cell.x.toDouble(), cell.y.toDouble());
      canvas.drawRect(
        Rect.fromLTWH(at.dx + gap, at.dy + gap, s - gap, s - gap),
        board.born.contains(cell) ? born : alive,
      );
    }

    // The patterns aityx recognized: an outline and the name.
    if (s < 3) return;
    final outline = Paint()
      ..color = Aityx.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final label in labels) {
      final c = label.cluster;
      if (c.maxX < visible.left ||
          c.minX > visible.right ||
          c.maxY < visible.top ||
          c.minY > visible.bottom) {
        continue;
      }
      final topLeft = camera.toView(c.minX - 0.5, c.minY - 0.5);
      final bottomRight = camera.toView(c.maxX + 1.5, c.maxY + 1.5);
      final box = Rect.fromPoints(topLeft, bottomRight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        outline,
      );
      final text = TextPainter(
        text: TextSpan(
          text: label.name,
          style: const TextStyle(
            color: Aityx.amber,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final pill = Rect.fromLTWH(
        box.left,
        box.top - text.height - 6,
        text.width + 10,
        text.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(4)),
        Paint()..color = Aityx.bg1.withValues(alpha: 0.9),
      );
      text.paint(canvas, Offset(pill.left + 5, pill.top + 2));
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.board != board || old.labels != labels || old.camera != camera;
}
